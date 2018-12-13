# Copyright (C) 2018 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package OpenQA::Worker::Cache::Task::Upload;
use Mojo::Base 'OpenQA::Worker::Cache::Task';

use Mojo::URL;

use constant LOCK_RETRY_DELAY   => 30;
use constant MINION_LOCK_EXPIRE => 99999;    # ~27 hours

use OpenQA::Worker::Cache::Client;
use OpenQA::Worker::Cache::Request;
use OpenQA::Worker::Uploader;

has uploader => sub { OpenQA::Worker::Uploader->from_worker };

sub register {
    my ($self, $app) = @_;

    $app->minion->add_task(
        upload_results => sub {
            my $job = shift;
            my ($id, $worker_job) = @_;
            my $req = OpenQA::Worker::Cache::Request->new->upload(
                id  => $id,
                job => $worker_job,
            );
            my $guard_name = $self->_gen_guard_name($req->lock);

            return $job->remove unless defined $worker_job && defined $worker_job->{id};
            return $job->retry({delay => LOCK_RETRY_DELAY})
              unless my $guard = $app->minion->guard($guard_name, MINION_LOCK_EXPIRE);

            my $job_prefix = "[Job #" . $job->id . "]";
            $app->log->debug("$job_prefix Guard: $guard_name Upload: results of job $guard_name");
            $app->log->debug("$job_prefix Dequeued " . $req->lock) if $self->_dequeue($req->lock);
            $OpenQA::Utils::app = undef;
            my $output;
            {
                open my $handle, '>', \$output;
                local *STDERR = $handle;
                local *STDOUT = $handle;

                # that is actually the line we want to invoke (FIXME: the whole code around it really required?)
                $self->uploader->upload_results();

                $job->finish($? >> 8);
                $job->note(output => $output);
            }
            $app->log->debug("${job_prefix} Finished");
        });
}

1;
