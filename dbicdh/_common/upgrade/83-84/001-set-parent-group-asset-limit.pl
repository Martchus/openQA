#!/usr/bin/env perl

# Copyright (C) 2019 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use strict;
use DBIx::Class::DeploymentHandler;
use OpenQA::Schema;
use OpenQA::Utils;
use Mojo::File;
use Mojo::JSON 'decode_json';

sub {
    my ($schema) = @_;

    OpenQA::Utils::log_info(
        'Default-initializing size limit for assets on parent level to sum of contained job groups.');

    my $limit_by_parent_group = decode_json(Mojo::File->new('/tmp/openqa-migration-83-84.json')->slurp);
    my $parent_groups         = $schema->resultset('JobGroupParents');
    while (my $parent_group = $parent_groups->next) {
        my $parent_id         = $parent_group->id;
        my $job_groups        = $parent_group->children;
        my $accumulated_limit = 0;
        while (my $job_group = $job_groups->next) {
            my $explicitly_set_size_limit = $job_group->get_column('size_limit_gb');
            if (defined $explicitly_set_size_limit) {
                $accumulated_limit += $explicitly_set_size_limit;
                next;
            }

            # the group was defaulting to the parent's value so let's add it here
            my $limit_inherited_by_parent_group = $limit_by_parent_group->{$parent_id};
            if (defined $limit_inherited_by_parent_group) {
                $accumulated_limit += $limit_inherited_by_parent_group;
                next;
            }
        }

        # just keep the default for empty parents (instead of assuming a limit of zero)
        next unless $accumulated_limit > 0;

        OpenQA::Utils::log_info(" -> setting size limit of parent $parent_id to $accumulated_limit GiB");
        $parent_group->update({size_limit_gb => $accumulated_limit});
    }
  }
