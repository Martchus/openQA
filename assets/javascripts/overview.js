/* jshint esversion: 6 */

function makeFaStack(shape, additionalClasses) {
  const className = additionalClasses + ' fa fa-stack-1x fa-' + shape;
  const firstElement = document.createElement('i');
  firstElement.className = className + '-o';
  firstElement.style.left = firstElement.style.top = '-1px';
  const secondElement = document.createElement('i');
  secondElement.className = className;
  secondElement.style.left = secondElement.style.top = '1px';
  const stackElement = document.createElement('span');
  stackElement.className = 'fa-stack';
  stackElement.appendChild(firstElement);
  stackElement.appendChild(secondElement);
  return stackElement;
}

function toggleParallelChildren(parentJobID) {
  const childRows = document.getElementsByClassName('parallel-child-of-' + parentJobID);
  for (let row = 0, rows = childRows.length; row != rows; ++row) {
    const style = childRows[row].style;
    style.display = style.display === 'none' ? 'table-row' : 'none';
  }
}

function stackParallelChildren(dependencyElement, dependencyInfo, visitedParents, visitedChildRows) {
  const relatedRow = dependencyElement.parentElement.parentElement;
  const parallelParents = dependencyInfo.parents.Parallel;
  const parallelChildren = dependencyInfo.children.Parallel;
  const relatedRes = dependencyElement.previousElementSibling;
  const relatedLink = relatedRes.firstElementChild;
  const jobIDMatch = (relatedRes.id || '').match(/\d+/);
  if (!jobIDMatch) {
    return false;
  }
  const jobID = jobIDMatch[0];
  visitedParents.push(jobID);
  if (Array.isArray(parallelChildren) && parallelChildren.length) {
    const relatedIcon = relatedLink.firstElementChild;
    relatedLink.replaceChild(makeFaStack('square', relatedIcon.className.replace(/fa-\w+/g, '')), relatedIcon);
    relatedLink.onclick = function () {
      toggleParallelChildren(jobID);
      return false;
    };
    // ensure children are shown after parents
    parallelChildren.forEach(childID => {
      const childRow = visitedChildRows[childID];
      if (childRow) {
        relatedRow.insertAdjacentElement('afterend', childRow);
      }
    });
  }
  if (Array.isArray(parallelParents) && parallelParents.length) {
    relatedRow.classList.add('parallel-child');
    parallelParents.forEach(parentID => relatedRow.classList.add('parallel-child-of-' + parentID));
    visitedChildRows[jobID] = relatedRow;
  }
}

function setupOverview() {
  setupLazyLoadingFailedSteps();
  $('.timeago').timeago();
  $('.cancel').bind('ajax:success', function (event, xhr, status) {
    $(this).text(''); // hide the icon
    var icon = $(this).parents('td').find('.status');
    icon.removeClass('state_scheduled').removeClass('state_running');
    icon.addClass('state_cancelled');
    icon.attr('title', 'Cancelled');
    icon.fadeTo('slow', 0.5).fadeTo('slow', 1.0);
  });
  $('.restart').bind('ajax:success', function (event, xhr, status) {
    if (typeof xhr !== 'object' || !Array.isArray(xhr.result)) {
      addFlash('danger', '<strong>Unable to restart job.</strong>');
      return;
    }
    showJobRestartResults(xhr, undefined, forceJobRestartViaRestartLink.bind(undefined, event.currentTarget));
    var newId = xhr.result[0];
    var oldId = 0;
    $.each(newId, function (key, value) {
      if (!$('.restart[data-jobid="' + key + '"]').length) {
        return true;
      }
      var restarted = $('.restart[data-jobid="' + key + '"]');
      restarted.text(''); // hide the icon
      var icon = restarted.parents('td').find('.status');
      icon.removeClass('state_done').removeClass('state_cancelled');
      icon.addClass('state_scheduled');
      icon.attr('title', 'Scheduled');
      // remove the result class
      restarted.parents('td').find('.result_passed').removeClass('result_passed');
      restarted.parents('td').find('.result_failed').removeClass('result_failed');
      restarted.parents('td').find('.result_softfailed').removeClass('result_softfailed');

      // If the API call returns a new id, a new job have been created to replace
      // the old one. In other case, the old job is being reused
      if (value) {
        var link = icon.parents('a');
        var oldId = restarted.data('jobid');
        var newUrl = link.attr('href').replace(oldId, value);
        link.attr('href', newUrl);
        link.addClass('restarted');
      }

      icon.fadeTo('slow', 0.5).fadeTo('slow', 1.0);
    });
  });
  const visitedParents = [];
  const visitedChildRows = {};
  var dependencies = document.getElementsByClassName('dependency');
  for (let i = 0; i < dependencies.length; i++) {
    const depElement = dependencies[i];
    var depInfo = depElement.dataset;
    var deps = JSON.parse(depInfo.deps);
    var dependencyResult = showJobDependency(deps);
    if (dependencyResult.title === undefined) {
      continue;
    }
    var elementIClass = 'fa fa-code-fork';
    var elementATitle = dependencyResult.title;
    if (deps.has_parents) {
      var str = parseInt(deps.parents_ok) ? 'passed' : 'failed';
      elementIClass += ' result_' + str;
      elementATitle += '\ndependency ' + str;
    }
    var elementA = document.createElement('a');
    elementA.href = '/tests/' + depInfo.jobid + '#dependencies';
    elementA.title = elementATitle;
    elementA.className = 'parents_children';
    elementA.dataset.childrenDeps = '[' + dependencyResult['data-children'].toString() + ']';
    elementA.dataset.parentsDeps = '[' + dependencyResult['data-parents'].toString() + ']';
    var elementI = document.createElement('i');
    elementI.setAttribute('class', elementIClass);
    elementA.appendChild(elementI);
    depElement.appendChild(elementA);
    stackParallelChildren(depElement, deps, visitedParents, visitedChildRows);
  }
  visitedParents.forEach(toggleParallelChildren);

  setupFilterForm();
  $('#filter-todo').prop('checked', false);

  // initialize filter for modules results
  var modulesResultFilter = $('#modules_result');
  modulesResultFilter.chosen({width: '100%'});
  modulesResultFilter.change(function (event) {
    // update query params
    var params = parseQueryParams();
    params.modules_results = modulesResultFilter.val();
  });

  modulesResultFilter.chosen({width: '100%'});

  // find specified results
  var results = {};
  var states = {};
  var modules_results = [];

  var formatFilter = function (filter) {
    return filter.replace(/_/g, ' ');
  };
  var filterLabels = parseFilterArguments(function (key, val) {
    if (key === 'result') {
      results[val] = true;
      return formatFilter(val);
    } else if (key === 'test') {
      $('#filter-test').prop('value', val);
      return val;
    } else if (key === 'state') {
      states[val] = true;
      return formatFilter(val);
    } else if (key === 'todo') {
      $('#filter-todo').prop('checked', val !== '0');
      return 'TODO';
    } else if (key === 'arch') {
      $('#filter-arch').prop('value', val);
      return val;
    } else if (key === 'flavor') {
      $('#filter-flavor').prop('value', val);
      return val;
    } else if (key === 'machine') {
      $('#filter-machine').prop('value', val);
      return val;
    } else if (key === 'module_re') {
      $('#filter-module-re').prop('value', val);
      return val;
    } else if (key === 'modules') {
      $('#modules').prop('value', val);
      return val;
    } else if (key === 'modules_result') {
      modules_results.push(val);
      modulesResultFilter.val(modules_results).trigger('chosen:updated').trigger('change');
      return formatFilter(val);
    }
  });

  // set enabled/disabled state of checkboxes (according to current filter)
  if (filterLabels.length > 0) {
    $('#filter-results input').each(function (index, element) {
      element.checked = results[element.id.substr(7)];
    });
    $('#filter-states input').each(function (index, element) {
      element.checked = states[element.id.substr(7)];
    });
  }

  var parentChild = document.getElementsByClassName('parents_children');
  for (let i = 0; i < parentChild.length; i++) {
    parentChild[i].addEventListener('mouseover', highlightDeps);
    parentChild[i].addEventListener('mouseout', unhighlightDeps);
  }
}

function highlightDeps() {
  var parentData = JSON.parse(this.dataset.parentsDeps);
  var childData = JSON.parse(this.dataset.childrenDeps);
  changeClassOfDependencyJob(parentData, 'highlight_parent', true);
  changeClassOfDependencyJob(childData, 'highlight_child', true);
}

function unhighlightDeps() {
  var parentData = JSON.parse(this.dataset.parentsDeps);
  var childData = JSON.parse(this.dataset.childrenDeps);
  changeClassOfDependencyJob(parentData, 'highlight_parent', false);
  changeClassOfDependencyJob(childData, 'highlight_child', false);
}

function changeClassOfDependencyJob(array, className, add) {
  for (var i = 0; i < array.length; i++) {
    const ele = document.getElementsByName('jobid_td_' + array[i])[0];
    if (ele === undefined) {
      continue;
    }
    const classList = ele.parentNode.classList;
    add ? classList.add(className) : classList.remove(className);
  }
}
