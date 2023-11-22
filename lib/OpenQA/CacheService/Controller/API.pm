# Copyright 2019 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::CacheService::Controller::API;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub info ($self) { $self->render(json => $self->minion->stats) }

sub _job ($self) {
    my $id = $self->param('id');
    return $self->render(json => {error => 'Specified job ID is invalid'}, status => 404)
      unless my $job = $self->minion->job($id);
    return $self->render(json => {error => "Minion job #$id info not available"}, status => 404)
      unless my $info = $job->info;
    return $self->render(json => {error => "Minion job #$id failed: $info->{result}"}, status => 500)
      if $info->{state} eq 'failed';
    return ($id, $job, $info);
}

sub status ($self) {
    my ($id, $job, $info) = $self->_job;
    return undef unless $info;

    # Our Minion job will finish early if another job is already downloading,
    # so we have to check if the lock has been released yet too
    my $status = {status => 'downloading'};
    my $notes = $info->{notes};
    if ($info->{state} eq 'finished' && !$self->progress->is_downloading($notes->{lock})) {
        $status = {
            status => 'processed',
            result => $info->{result},
            output => $notes->{output},
            has_download_error => $notes->{has_download_error}};

        # Output from the job that actually did the download
        if (my $id = $info->{notes}{downloading_job}) {
            if (my $job = $self->minion->job($id)) {
                if (my $info = $job->info) {
                    return $self->render(json => {error => "Minion job #$id failed: $info->{result}"}, status => 500)
                      if $info->{state} eq 'failed';
                    $status->{output} = $info->{notes}{output} if $info->{state} eq 'finished';
                }
            }
        }
    }

    $self->render(json => $status);
}

sub withdraw ($self) {
    my ($id, $job) = $self->_job;
    return undef unless $job;
    return $self->render(json => 'removed inactive/finished/failed job') if $job->remove;
    $job->kill('USR1');
    $self->render(json => 'sent USR1 to running job');
    #my $ref_count = --$info->{notes}->{ref_count};
    #if ($ref_count > 0) {
    #    $job->note(ref_count => $ref_count);
    #    return $self->render(json => "decremented ref count of running job to $ref_count")
    #} else {
    #    $job->kill('TERM');
    #    return $self->render(json => 'sent TERM to job')
    #}
}

# create `cache_tests` jobs with increased prio because many jobs can benefit/proceed if they
# are processed (as the have only a few number of test distributions compared to the number
# different assets)
my %DEFAULT_PRIO_BY_TASK = (cache_tests => 10);

sub enqueue ($self) {
    my $data = $self->req->json;
    return $self->render(json => {error => 'No task defined'}, status => 400)
      unless defined(my $task = $data->{task});
    return $self->render(json => {error => 'No arguments defined'}, status => 400)
      unless defined(my $args = $data->{args});
    return $self->render(json => {error => 'Arguments need to be an array'}, status => 400)
      unless ref $args eq 'ARRAY';
    return $self->render(json => {error => 'No lock defined'}, status => 400)
      unless defined(my $lock = $data->{lock});

    $self->app->log->debug("Requested [$task] Args: @{$args} Lock: $lock");

    my $prio = $data->{priority} // ($DEFAULT_PRIO_BY_TASK{$task} // 0);
    my $id = $self->minion->enqueue($task => $args => {notes => {lock => $lock, ref_count => 1}, priority => $prio});
    $self->render(json => {status => 'downloading', id => $id});
}

1;
