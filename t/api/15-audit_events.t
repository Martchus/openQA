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

use Mojo::Base -strict;

BEGIN {
    unshift @INC, 'lib';
}

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Test::Mojo;
use OpenQA::Test::Database;
use OpenQA::Test::Case;

my $schema = OpenQA::Test::Case->new->init_data;
my $t      = Test::Mojo->new('OpenQA::WebAPI');
my $app    = $t->app;
$t->ua(OpenQA::Client->new(apikey => 'ARTHURKEY01', apisecret => 'EXCALIBUR')->ioloop(Mojo::IOLoop->singleton));
$t->app($app);

subtest 'triggering audit event cleanup' => sub {
    $t->delete_ok('/api/v1/audit_events/trigger_cleanup')->status_is(200);
    ok(my $gru_task_id = $t->tx->res->json->{gru_task_id}, 'gru task ID returned');
    my $gru_task = $schema->resultset('GruTasks')->find($gru_task_id);
    ok($gru_task, 'gru task added');
    is($gru_task->taskname, 'limit_audit_events', 'limit_audit_events task enqueued');
};

done_testing();
