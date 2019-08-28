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
use warnings;
use DBIx::Class::DeploymentHandler;
use OpenQA::Utils;

sub {
    my ($schema) = @_;

    # ensure Gru plugin is loaded at this point
    # note: This needs to be done manually because plugins are generally not loaded until the deployment has finished
    #       because they generally depend on the database being already deployed yet.
    my $app = $OpenQA::Utils::app;
    if (!$app->can('gru')) {
        push @{$app->plugins->namespaces}, 'OpenQA::WebAPI::Plugin';
        $app->plugin('Gru');
    }

    log_info('Scheduling database migration to add link count to screenshots table. This might take a while.');
    $app->gru->enqueue(populate_screenshot_link_count => {});
}
