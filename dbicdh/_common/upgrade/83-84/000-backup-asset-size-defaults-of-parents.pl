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
use Mojo::JSON 'encode_json';

sub {
    my ($schema) = @_;

    OpenQA::Utils::log_info('Writing default asset limits of parent groups to temporary file.');

    # note: Using manual query here because the script is executed before the "auto" migration of DBIx
    #       which would assume that the migration has already happened.

    my $dbh   = $schema->storage->dbh;
    my $query = $dbh->prepare('select id, default_size_limit_gb from job_group_parents;');
    $query->execute;

    my %limit_by_parent_group;
    while (my $row = $query->fetchrow_hashref) {
        $limit_by_parent_group{$row->{id}} = $row->{default_size_limit_gb};
    }
    Mojo::File->new('/tmp/openqa-migration-83-84.json')->spurt(encode_json(\%limit_by_parent_group));
  }
