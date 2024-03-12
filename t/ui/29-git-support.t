#!/usr/bin/env perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;

use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../external/os-autoinst-common/lib";
use Test::Mojo;
use Test::Warnings qw(:all :report_warnings);
use Mojo::JSON qw(encode_json);
use Mojo::File qw(path tempdir);
use OpenQA::Test::TimeLimit '40';
use OpenQA::Test::Case;
use OpenQA::Test::Utils qw(prepare_clean_needles_dir prepare_default_needle);
use OpenQA::SeleniumTest;

$ENV{OPENQA_CONFIG} = my $config_dir = tempdir("$FindBin::Script-XXXX");
$config_dir->child('openqa.ini')->spew("[scm git]\ncheckout_needles_sha = yes\n");

my $test_case = OpenQA::Test::Case->new;
my $schema_name = OpenQA::Test::Database->generate_schema_name;
my $schema = $test_case->init_data(
    schema_name => $schema_name,
    fixtures_glob => '01-jobs.pl ui-18-tests-details/01-job_modules.pl 07-needles.pl'
);

# prepare needles dir
my $needle_dir_fixture = $schema->resultset('NeedleDirs')->find(1);
my $needle_dir = prepare_clean_needles_dir;
prepare_default_needle($needle_dir);
$needle_dir_fixture->update({path => $needle_dir->realpath});

# FIXME: create needle JSON and PNG - maybe even in a previous commit which we can put in NEEDLES_GIT_HASH

# prepare job
my $jobs = $schema->resultset('Jobs');
my $job = $jobs->find(99937);
$job->settings->create({key => 'NEEDLES_DIR', value => 'https://github.com/os-autoinst/openQA'});
path($job->result_dir, 'vars.json')->spew(encode_json({NEEDLES_GIT_HASH => 'foo'}));

driver_missing unless my $driver = call_driver;

$driver->get('/tests/99937');
disable_bootstrap_animations;
sleep 10000;

kill_driver();
done_testing();
