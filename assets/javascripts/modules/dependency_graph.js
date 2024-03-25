import * as d3-array from '/node_modules/d3-array/array.js';
import * as d3 from '/node_modules/d3/src/index.js';
import * as dagreD3 from '/node_modules/dagre-d3-es/src/index.js';

function renderDependencyGraph(container, nodes, edges, cluster, currentNode) {
  // create a new directed graph
  var g = new dagreD3.graphlib.Graph({compound: true}).setGraph({});

  // set left-to-right layout and spacing
  g.setGraph({
    rankdir: 'LR',
    nodesep: 10,
    ranksep: 50,
    marginx: 10,
    marginy: 10
  });

  // insert nodes
  const nodeIDs = {};
  nodes.forEach(node => {
    var testResultId;
    if (node.result !== 'none') {
      testResultId = node.result;
    } else {
      testResultId = node.state;
      if (testResultId === 'scheduled' && node.blocked_by_id) {
        testResultId = 'blocked';
      }
    }
    var testResultName = testResultId.replace(/_/g, ' ');

    g.setNode(node.id, {
      label: function () {
        var table = document.createElement('table');
        table.id = 'nodeTable' + node.id;
        var tr = d3.select(table).append('tr');

        var testNameTd = tr.append('td');
        if (node.id == currentNode) {
          testNameTd.text(node.label);
          tr.node().className = 'current';
        } else {
          var testNameLink = testNameTd.append('a');
          testNameLink.attr('href', urlWithBase('/tests/' + node.id) + '#dependencies');
          testNameLink.text(node.label);
        }

        var testResultTd = tr.append('td');
        testResultTd.text(testResultName);
        testResultTd.node().className = testResultId;

        return table;
      },
      padding: 0,
      name: node.name,
      testResultId: testResultId,
      testResultName: testResultName,
      startAfter: node.chained,
      startDirectlyAfter: node.directly_chained,
      parallelWith: node.parallel
    });
    nodeIDs[node.id] = true;
  });

  // insert edges
  edges
    .sort((a, b) => a.from - b.from || a.to - b.to)
    .forEach(edge => {
      if (nodeIDs[edge.from] && nodeIDs[edge.to]) {
        g.setEdge(edge.from, edge.to, {});
      }
    });

  // insert clusters
  Object.keys(cluster).forEach(clusterId => {
    g.setNode(clusterId, {});
    cluster[clusterId].forEach(child => {
      if (nodeIDs[child]) {
        g.setParent(child, clusterId);
      }
    });
  });

  // create the renderer
  var render = new dagreD3.render();

  // set up an SVG group so that we can translate the final graph.
  var svg = d3.select('svg'),
    svgGroup = svg.append('g');

  // run the renderer (this is what draws the final graph)
  render(svgGroup, g);

  // add tooltips
  svgGroup
    .selectAll('g.node')
    .attr('title', function (v) {
      var node = g.node(v);
      var tooltipText = '<p>' + node.name + '</p>';
      var startAfter = node.startAfter;
      var startDirectlyAfter = node.startDirectlyAfter;
      var parallelWith = node.parallelWith;
      if (startAfter.length || startDirectlyAfter.length || parallelWith.length) {
        tooltipText += '<div style="border-top: 1px solid rgba(100, 100, 100, 30); margin: 5px 0px;"></div>';
        if (startAfter.length) {
          tooltipText += '<p><code>START_AFTER_TEST=' + htmlEscape(startAfter.join(',')) + '</code></p>';
        }
        if (startDirectlyAfter.length) {
          tooltipText +=
            '<p><code>START_DIRECTLY_AFTER_TEST=' + htmlEscape(startDirectlyAfter.join(',')) + '</code></p>';
        }
        if (parallelWith.length) {
          tooltipText += '<p><code>PARALLEL_WITH=' + htmlEscape(parallelWith.join(',')) + '</code></p>';
        }
      }
      return tooltipText;
    })
    .each(function (v) {
      $(this).tooltip({
        html: true,
        placement: 'right'
      });
    });

  // move the graph a bit to the bottom so lines at the top are not clipped
  svgGroup.attr('transform', 'translate(0, 20)');

  // set width and height of the svg element to the graph's size plus a bit extra spacing
  svg.attr('width', g.graph().width + 40);
  svg.attr('height', g.graph().height + 40);

  // note: centering is achieved by centering the svg element itself like any other html block element
}

function rescheduleProductForJob(link) {
  if (window.confirm('Do you really want to partially reschedule the product of this job?')) {
    rescheduleProduct(link.dataset.url);
  }
  return false; // avoid usual link handling
}
