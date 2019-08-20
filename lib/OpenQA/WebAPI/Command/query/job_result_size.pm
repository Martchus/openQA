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

package OpenQA::WebAPI::Command::query::job_result_size;
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
        log_debug("Skipping non-existant results dir: $results_dir") if defined $results_dir;
        return undef;
    }
    log_info("Checking results dir: $results_dir");
    return _getDirSize($results_dir);
}

sub run {
    my ($self, @args) = @_;

    my $app    = $self->app;
    my $schema = $app->schema;

    my $job_groups = $schema->resultset('JobGroups');
    my $jobs       = $schema->resultset('Jobs');

    $app->log->level('info');

    my @job_groups_with_size;
    while (my $job_group = $job_groups->next) {
        my $jobs           = $job_group->jobs;
        my $job_count      = 0;
        my $job_group_size = 0;
        while (my $job = $jobs->next) {
            my $job_size = _check_job_size($job);
            next unless defined $job_size;
            $job_count      += 1;
            $job_group_size += $job_size;
        }
        push(
            @job_groups_with_size,
            {
                id               => $job_group->id,
                name             => $job_group->name,
                size             => $job_group_size,
                size_str         => human_readable_size($job_group_size),
                job_count        => $job_count,
                average_job_size => $job_count ? $job_group_size / $job_count : 0,
            });
    }

    my $groupless_jobs       = $jobs->search({group_id => undef});
    my $groupless_jobs_size  = 0;
    my $groupless_jobs_count = 0;
    while (my $job = $groupless_jobs->next) {
        my $job_size = _check_job_size($job);
        next unless defined $job_size;
        $groupless_jobs_count += 1;
        $groupless_jobs_size  += $job_size;
    }
    push(
        @job_groups_with_size,
        {
            size             => $groupless_jobs_size,
            size_str         => human_readable_size($groupless_jobs_size),
            job_count        => $groupless_jobs_count,
            average_job_size => $groupless_jobs_count ? $groupless_jobs_size / $groupless_jobs_count : 0,
        });

    my @job_groups_sorted_by_size = sort { $a->{size} <=> $b->{size} } @job_groups_with_size;
    print('results: ');
    print(pp(\@job_groups_sorted_by_size));
    print("\n");
}

1;

