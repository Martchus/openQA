# Copyright (C) 2019 SUSE LLC
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

package OpenQA::WebAPI::Command::query::job_result_size_estimate;
use Mojo::Base 'Mojolicious::Commands';

use OpenQA::Utils qw(log_debug log_info human_readable_size);
use Data::Dump 'pp';

has description => 'Computes the disk space used for job results/logs grouped by job groups';
has usage       => sub { shift->extract_usage };

sub _getDirSize {
    my ($dir, $size) = @_;
    $size //= 0;

    opendir(my $dh, $dir) || return 0;
    for my $dirContent (readdir($dh)) {
        next if $dirContent eq '.' || $dirContent eq '..';
        $dirContent = "$dir/$dirContent";
        if (-f $dirContent) {
            my $fsize = -s $dirContent;
            $size += $fsize;
        }
        elsif (-d $dirContent) {
            $size = _getDirSize($dirContent, $size);
        }
    }
    closedir($dh);
    return $size;
}

sub _check_job_size {
    my ($job) = @_;

    my $results_dir = $job->result_dir;
    if (!defined $results_dir || !-d $results_dir) {
        print("Skipping non-existant results dir: $results_dir\n") if defined $results_dir;
        return undef;
    }
    print("Checking results dir: $results_dir\n");
    return _getDirSize($results_dir);
}

sub run {
    my ($self, @args) = @_;

    my $app    = $self->app;
    my $schema = $app->schema;

    my $job_groups = $schema->resultset('JobGroups');
    my $jobs       = $schema->resultset('Jobs');

    $app->log->level('info');

    # pick 1000 random jobs without logs to get average result size without logs
    my $sample_size = 1000;
    my @query = (result_dir => {-not => undef});
    my %params = (order_by => \"random()", rows => $sample_size);
    my $jobs_without_logs = $jobs->search({@query, logs_present => 0}, \%params);
    my $result_size_without_logs = 0;
    while (my $job = $jobs_without_logs->next) {
        my $job_size = _check_job_size($job) or next;
        $result_size_without_logs += $job_size;
    }
    my $average_result_size_without_logs = $result_size_without_logs / $sample_size;
    print("Average result size without logs: $average_result_size_without_logs\n");

    # pick 1000 random jobs with logs to get average result size with logs
    my $jobs_with_logs = $jobs->search({@query, logs_present => 1}, \%params);
    my $result_size_with_logs = 0;
    while (my $job = $jobs_with_logs->next) {
        my $job_size = _check_job_size($job) or next;
        $result_size_with_logs += $job_size;
    }
    my $average_result_size_with_logs = $result_size_with_logs / $sample_size;
    print("Average result size with logs: $average_result_size_with_logs\n");

    my $average_log_size = ($result_size_with_logs - $result_size_without_logs) / $sample_size;
    print("Average log size: $average_log_size\n");

    # estimate result dir size by group using average sizes
    my @job_groups_with_size;
    while (my $job_group = $job_groups->next) {
        my $jobs           = $job_group->jobs;
        my $job_count      = 0;
        my $job_group_size = 0;

        my @query = (group_id => $job_group->id, result_dir => {-not => undef});
        my $jobs_without_logs = $jobs->search({@query, logs_present => 0})->count;
        my $jobs_with_logs = $jobs->search({@query, logs_present => 1})->count;
        my $size = $jobs_without_logs * $average_result_size_without_logs + $jobs_with_logs * $average_result_size_with_logs;
        push(
            @job_groups_with_size,
            {
                id               => $job_group->id,
                name             => $job_group->name,
                jobs_without_logs => $jobs_without_logs,
                jobs_with_logs    => $jobs_with_logs,
                total_job_count   => $jobs_without_logs + $jobs_with_logs,
                size              => $size,
                size_str          => human_readable_size($size),
            });
    }

    my @groupless_query = (group_id => undef, result_dir => {-not => undef});
    my $groupless_jobs_without_logs = $jobs->search({@groupless_query, logs_present => 0})->count;
    my $groupless_jobs_with_logs = $jobs->search({@groupless_query, logs_present => 1})->count;
    my $size = $groupless_jobs_without_logs * $average_result_size_without_logs + $groupless_jobs_with_logs * $average_result_size_with_logs;
    push(
        @job_groups_with_size,
        {
            jobs_without_logs => $groupless_jobs_without_logs,
            jobs_with_logs    => $groupless_jobs_with_logs,
            total_job_count   => $groupless_jobs_without_logs + $groupless_jobs_with_logs,
            size              => $size,
            size_str          => human_readable_size($size),
        });

    my @job_groups_sorted_by_size = sort { $a->{size} <=> $b->{size} } @job_groups_with_size;
    print('results: ');
    print(pp(\@job_groups_sorted_by_size));
    print("\n");
}

1;

