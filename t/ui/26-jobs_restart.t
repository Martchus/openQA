# Copyright (C) 2018 SUSE Linux GmbH
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

use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Test::Mojo;
use Test::Warnings;
use OpenQA::Test::Case;
use OpenQA::SeleniumTest;
use Date::Format 'time2str';

OpenQA::Test::Case->new->init_data;

my $t = Test::Mojo->new('OpenQA::WebAPI');

sub schema_hook {
    my $schema = OpenQA::Test::Database->new->create;
    my $jobs   = $schema->resultset('Jobs');

    # Populate more cluster jobs
    my @test_names = ('create_hdd', 'support_server', 'master_node', 'slave_node');
    for my $n (0 .. 3) {
        my $new = {
            id          => 99900 + $n,
            group_id    => 1001,
            priority    => 35,
            result      => 'failed',
            state       => "done",
            backend     => 'qemu',
            t_finished  => time2str('%Y-%m-%d %H:%M:%S', time - 576600, 'UTC'),
            t_started   => time2str('%Y-%m-%d %H:%M:%S', time - 576000, 'UTC'),
            t_created   => time2str('%Y-%m-%d %H:%M:%S', time - 7200, 'UTC'),
            TEST        => $test_names[$n],
            FLAVOR      => 'DVD',
            DISTRI      => 'opensuse',
            BUILD       => '0091',
            VERSION     => '13.1',
            MACHINE     => '32bit',
            ARCH        => 'i586',
            jobs_assets => [{asset_id => 1},],
            settings    => [
                {key => 'QEMUCPU',     value => 'qemu32'},
                {key => 'DVD',         value => '1'},
                {key => 'VIDEOMODE',   value => 'text'},
                {key => 'ISO',         value => 'openSUSE-13.1-DVD-i586-Build0091-Media.iso'},
                {key => 'DESKTOP',     value => 'textmode'},
                {key => 'ISO_MAXSIZE', value => '4700372992'}]};
        $jobs->create($new);
    }
    $jobs->find(99900)->children->create(
        {
            child_job_id => 99901,
            dependency   => OpenQA::JobDependencies::Constants::CHAINED,
        });
    $jobs->find(99901)->children->create(
        {
            child_job_id => 99902,
            dependency   => OpenQA::JobDependencies::Constants::PARALLEL,
        });
    $jobs->find(99901)->children->create(
        {
            child_job_id => 99903,
            dependency   => OpenQA::JobDependencies::Constants::PARALLEL,
        });
}

my $driver = call_driver(\&schema_hook);
unless ($driver) {
    plan skip_all => $OpenQA::SeleniumTest::drivermissing;
    exit(0);
}

$driver->title_is('openQA', 'on main page');
$driver->find_element_by_link_text('Login')->click();
is($driver->get('/tests'), 1, 'get /tests page');
wait_for_ajax();

subtest 'check single job restart in /tests page' => sub {
    # Restart a single job
    my $td = $driver->find_element('#job_99936 td.test');
    is($td->get_text(), 'kde@64bit-uefi', '99936 is kde@64bit-uefi');
    $driver->find_child_element($td, '.restart', 'css')->click();
    wait_for_ajax();

    # Check if job is marked as restartd and restart link is correct
    is($td->get_text(), 'kde@64bit-uefi (restarted)', '99936 is marked as restarted');
    my $restart_link = $driver->find_child_element($td, "./a[\@title='new test']", 'xpath')->get_attribute('href');
    like($restart_link, qr|tests/99982|, 'restart link is correct');

    # Open restart link then verify its test name
    $driver->find_child_element($td, "./a[\@title='new test']", 'xpath')->click();
    like($driver->find_element('#info_box .card-header')->get_text(), qr/kde\@64bit-uefi/, 'restarted job is correct');
};

ok($driver->get('/tests'), 'back on /tests page');
wait_for_ajax();

my $first_tab = $driver->get_current_window_handle();
my $second_tab;

subtest 'check cluster jobs restart in /tests page' => sub {
    # Check chain jobs restart
    my $chained_parent = $driver->find_element('#job_99937 td.test');
    my $chained_child  = $driver->find_element('#job_99938 td.test');
    is($chained_parent->get_text(), 'kde@32bit', 'chained parent is kde@32bit');
    is($chained_child->get_text(),  'doc@64bit', 'chained child is doc@64bit');

    # Restart chained parent job
    $driver->find_child_element($chained_parent, '.restart', 'css')->click();
    wait_for_ajax();

    # Chained parent and its child should be marked as restarted
    is($chained_parent->get_text(), 'kde@32bit (restarted)', 'chained parent is marked as restarted');
    is($chained_child->get_text(),  'doc@64bit (restarted)', 'chained child is marked as restarted');

    # Check if restart links are correct
    my $parent_restart_link
      = $driver->find_child_element($chained_parent, "./a[\@title='new test']", 'xpath')->get_attribute('href');
    my $child_restart_link
      = $driver->find_child_element($chained_child, "./a[\@title='new test']", 'xpath')->get_attribute('href');
    like($parent_restart_link, qr|tests/99983|, 'restart link is correct');
    like($child_restart_link,  qr|tests/99984|, 'restart link is correct');

    # Open tab for each restart link then verify its test name
    $second_tab = open_new_tab($parent_restart_link);
    $driver->switch_to_window($second_tab);
    like($driver->find_element('#info_box .card-header')->get_text(),
        qr/kde\@32bit/, 'restarted chained parent is correct');
    $driver->close();
    $driver->switch_to_window($first_tab);
    $second_tab = open_new_tab($child_restart_link);
    $driver->switch_to_window($second_tab);
    like($driver->find_element('#info_box .card-header')->get_text(),
        qr/doc\@64bit/, 'restarted chained child is correct');
    $driver->close();
    $driver->switch_to_window($first_tab);
    is($driver->get_title(), 'openQA: Test results', 'back to /tests page');

    # Check parallel jobs restart in page 2 of finished jobs
    my @page_next = $driver->find_elements('#results_next .page-link');
    (shift(@page_next))->click();
    wait_for_ajax();

    my $master_node    = $driver->find_element('#job_99902 td.test');
    my $slave_node     = $driver->find_element('#job_99903 td.test');
    my $support_server = $driver->find_element('#job_99901 td.test');
    is($master_node->get_text(),    'master_node@32bit',    'a parallel child is master_node@32bit');
    is($slave_node->get_text(),     'slave_node@32bit',     'a parallel child is slave_node@32bit');
    is($support_server->get_text(), 'support_server@32bit', 'a parallel parent is support_server@32bit');

    # Restart a parallel job
    $driver->find_child_element($master_node, '.restart', 'css')->click();
    wait_for_ajax();

    # All parallel jobs and their parent job should be marked as restarted
    is($master_node->get_text(), 'master_node@32bit (restarted)', 'parallel child master_node is marked as restarted');
    is($slave_node->get_text(),  'slave_node@32bit (restarted)',  'parallel child slave_node is marked as restarted');
    is(
        $support_server->get_text(),
        'support_server@32bit (restarted)',
        'parallel parent support_server is marked as restarted'
    );

    # Check if restart links are correct
    my $master_node_link
      = $driver->find_child_element($master_node, "./a[\@title='new test']", 'xpath')->get_attribute('href');
    my $slave_node_link
      = $driver->find_child_element($slave_node, "./a[\@title='new test']", 'xpath')->get_attribute('href');
    my $support_server_link
      = $driver->find_child_element($support_server, "./a[\@title='new test']", 'xpath')->get_attribute('href');
    like($master_node_link,    qr|tests/99986|, 'restart link is correct');
    like($slave_node_link,     qr|tests/99987|, 'restart link is correct');
    like($support_server_link, qr|tests/99985|, 'restart link is correct');

    # Open tab for each restart link then verify its test name
    $second_tab = open_new_tab($master_node_link);
    $driver->switch_to_window($second_tab);
    like($driver->find_element('#info_box .card-header')->get_text(),
        qr/master_node\@32bit/, 'restarted parallel child is correct');
    $driver->close();
    $driver->switch_to_window($first_tab);
    $second_tab = open_new_tab($slave_node_link);
    $driver->switch_to_window($second_tab);
    like($driver->find_element('#info_box .card-header')->get_text(),
        qr/slave_node\@32bit/, 'restarted parallel child is correct');
    $driver->close();
    $driver->switch_to_window($first_tab);
    $second_tab = open_new_tab($support_server_link);
    $driver->switch_to_window($second_tab);
    like($driver->find_element('#info_box .card-header')->get_text(),
        qr/support_server\@32bit/, 'restarted parallel parent is correct');
    $driver->close();
    $driver->switch_to_window($first_tab);
    is($driver->get_title(), 'openQA: Test results', 'back to /tests page');
};

subtest 'check cluster jobs restart in test overview page' => sub {
    # Refresh /tests page and cancel all 6 restarted jobs in previous tests
    ok($driver->get('/tests'), 'back on /tests page');
    wait_for_ajax();
    my @scheduled_tds = $driver->find_elements('#scheduled td.test');
    for my $i (0 .. 5) {
        $driver->find_child_element($scheduled_tds[$i], '.cancel', 'css')->click();
    }

    # Restart a parent job in test results overview page
    is($driver->get('/tests/overview?distri=opensuse&version=13.1&build=0091&groupid=1001'),
        1, 'go to test overview page');
    $driver->find_element('#res_DVD_i586_create_hdd .restart')->click();
    wait_for_ajax();

    # All related cluster jobs should be marked as restarted
    is($driver->find_element('#res_DVD_i586_create_hdd .fa-circle')->get_attribute('title'),
        'Scheduled', 'create_hdd is restarted');
    is($driver->find_element('#res_DVD_i586_support_server .fa-circle')->get_attribute('title'),
        'Scheduled', 'support_server is restarted');
    is($driver->find_element('#res_DVD_i586_master_node .fa-circle')->get_attribute('title'),
        'Scheduled', 'master_node is restarted');
    is($driver->find_element('#res_DVD_i586_slave_node .fa-circle')->get_attribute('title'),
        'Scheduled', 'slave_node is restarted');

    # Check restart links if replaced
    like($driver->find_element('#res_DVD_i586_create_hdd .restarted')->get_attribute('href'),
        qr|tests/99988|, 'restarted link is correct');
    like($driver->find_element('#res_DVD_i586_support_server .restarted')->get_attribute('href'),
        qr|tests/99989|, 'restarted link is correct');
    like($driver->find_element('#res_DVD_i586_master_node .restarted')->get_attribute('href'),
        qr|tests/99990|, 'restarted link is correct');
    like($driver->find_element('#res_DVD_i586_slave_node .restarted')->get_attribute('href'),
        qr|tests/99991|, 'restarted link is correct');
};

subtest 'check job restart from infopanel in test results' => sub {
    is($driver->get('/tests/99926'), 1, 'go to job 99926');
    $driver->find_element('#restart-result')->click();
    wait_for_ajax();
    like($driver->get_current_url(), qr|tests/99992|, 'auto refresh to restarted job 99992');
    like($driver->find_element('#info_box .card-header')->get_text(), qr/minimalx\@32bit/, 'restarted job is correct');
};

kill_driver();
done_testing();
