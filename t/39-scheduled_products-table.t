#! /usr/bin/perl

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
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

BEGIN {
    unshift @INC, 'lib';
    $ENV{OPENQA_TEST_IPC} = 1;
}

use FindBin;
use lib "$FindBin::Bin/lib";
use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use Test::Warnings;
use Test::MockModule;
use Test::Exception;
use OpenQA::Test::Case;
use OpenQA::Utils;

# init test case
my $test_case = OpenQA::Test::Case->new;
$test_case->init_data;
my $t = Test::Mojo->new('OpenQA::WebAPI');

my $schema             = $t->app->schema;
my $scheduled_products = $schema->resultset('ScheduledProducts');
my %settings           = (
    distri   => 'openSUSE',
    version  => '15.1',
    flavor   => 'DVD',
    arch     => 'x86_64',
    build    => 'foo',
    settings => {some => 'settings'},
    user_id  => 99901,
);

# prevent job creation
my $scheduled_products_mock = Test::MockModule->new('OpenQA::Schema::Result::ScheduledProducts');
$scheduled_products_mock->mock(_generate_jobs => sub { return undef; });

my $scheduled_product;
subtest 'handling assets with invalid name' => sub {
    $scheduled_product = $scheduled_products->create(\%settings);

    is_deeply(
        $scheduled_product->schedule_iso({REPO_0 => ''}),
        {error => 'Asset type and name must not be empty.'},
        'schedule_iso prevents adding assets with empty name',
    );

    $scheduled_product->discard_changes;
    is(
        $scheduled_product->status,
        OpenQA::Schema::Result::ScheduledProducts::SCHEDULED,
        'product marked as scheduled, though'
    );

    $scheduled_product = $scheduled_products->create(\%settings);
    is_deeply(
        $scheduled_product->schedule_iso({REPO_0 => 'invalid'}),
        {
            successful_job_ids => [],
            failed_job_info    => [],
        },
        'schedule_iso allows non-existant assets though',
    );

    $scheduled_product->discard_changes;
    is(
        $scheduled_product->status,
        OpenQA::Schema::Result::ScheduledProducts::SCHEDULED,
        'product marked as scheduled, though'
    );
};

dies_ok(sub { $scheduled_product->schedule_iso(\%settings); }, 'scheduling the same product again prevented');

done_testing();
