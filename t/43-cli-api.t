# Copyright (C) 2020 SUSE Linux Products GmbH
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

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More;
use Capture::Tiny qw(capture_stdout);
use Mojo::Server::Daemon;
use Mojo::JSON 'decode_json';
use Mojo::File 'tempfile';
use OpenQA::CLI;
use OpenQA::CLI::api;
use OpenQA::Test::Case;

OpenQA::Test::Case->new->init_data;

# Mock WebAPI with extra test routes
my $daemon = Mojo::Server::Daemon->new(listen => ['http://127.0.0.1']);
my $app    = $daemon->build_app('OpenQA::WebAPI');
$app->log->level('error');
my $port = $daemon->start->ports->[0];
my $host = "http://127.0.0.1:$port";

# Test routes
my $op = $app->routes->find('api_ensure_operator');
$op->get('/test/op/hello' => sub { shift->render(text => 'Hello operator!') });
my $pub = $app->routes->find('api_public');
$pub->any(
    '/test/pub/http' => sub {
        my $c    = shift;
        my $req  = $c->req;
        my $data = {method => $req->method, headers => $req->headers->to_hash, body => $req->body};
        $c->render(json => $data);
    });

# Default options for mock server
my @host = ('-H', $host);

# Default options for authentication tests
my @auth = ('--apikey', 'ARTHURKEY01', '--apisecret', 'EXCALIBUR', @host);

my $cli = OpenQA::CLI->new;
my $api = OpenQA::CLI::api->new;

subtest 'Help' => sub {
    my ($stdout, @result) = capture_stdout sub { $cli->run('help', 'api') };
    like $stdout, qr/Usage: openqa-cli api/, 'help';
};

subtest 'Client' => sub {
    isa_ok $api->client, 'OpenQA::Client', 'right class';
};

subtest 'Simple request with authentication' => sub {
    my ($stdout, @result) = capture_stdout sub { $api->run(@host, '/api/v1/test/op/hello') };
    like $stdout, qr/403/, 'not authenticated';

    ($stdout, @result) = capture_stdout sub { $api->run(@auth, '/api/v1/test/op/hello') };
    like $stdout, qr/Hello operator!/, 'operator response';
};

subtest 'HTTP features' => sub {
    my ($stdout, @result) = capture_stdout sub { $api->run('--host', $host, '/api/v1/test/pub/http') };
    my $data = decode_json $stdout;
    is $data->{method}, 'GET', 'GET request';

    ($stdout, @result) = capture_stdout sub { $api->run(@host, '/api/v1/test/pub/http') };
    $data = decode_json $stdout;
    is $data->{method}, 'GET', 'GET request';

    ($stdout, @result) = capture_stdout sub { $api->run(@host, '-X', 'POST', '/api/v1/test/pub/http') };
    $data = decode_json $stdout;
    is $data->{method}, 'POST', 'POST request';

    ($stdout, @result) = capture_stdout sub { $api->run(@host, '--method', 'POST', '/api/v1/test/pub/http') };
    $data = decode_json $stdout;
    is $data->{method}, 'POST', 'POST request';

    ($stdout, @result) = capture_stdout sub { $api->run(@host, '-d', 'Hello openQA!', '/api/v1/test/pub/http') };
    $data = decode_json $stdout;
    is $data->{body}, 'Hello openQA!', 'request body';

    ($stdout, @result) = capture_stdout sub { $api->run(@host, '--data', 'Hello openQA!', '/api/v1/test/pub/http') };
    $data = decode_json $stdout;
    is $data->{body}, 'Hello openQA!', 'request body';

    ($stdout, @result)
      = capture_stdout sub { $api->run(@host, '-a', 'X-Test: works', '/api/v1/test/pub/http') };
    $data = decode_json $stdout;
    is $data->{headers}{'X-Test'}, 'works', 'X-Test header';

    ($stdout, @result)
      = capture_stdout sub { $api->run(@host, '--header', 'X-Test: works', '/api/v1/test/pub/http') };
    $data = decode_json $stdout;
    is $data->{headers}{'X-Test'}, 'works', 'X-Test header';

    ($stdout, @result)
      = capture_stdout
      sub { $api->run(@host, '-a', 'X-Test: works', '-a', 'X-Test2: works too', '/api/v1/test/pub/http') };
    $data = decode_json $stdout;
    is $data->{headers}{'X-Test'},  'works',     'X-Test header';
    is $data->{headers}{'X-Test2'}, 'works too', 'X-Test2 header';

    ($stdout, @result)
      = capture_stdout
      sub { $api->run(@host, '--header', 'X-Test: works', '--header', 'X-Test2: works too', '/api/v1/test/pub/http') };
    $data = decode_json $stdout;
    is $data->{headers}{'X-Test'},  'works',     'X-Test header';
    is $data->{headers}{'X-Test2'}, 'works too', 'X-Test2 header';

    ($stdout, @result)
      = capture_stdout
      sub { $api->run(@host, '-X', 'POST', '-a', 'Accept: application/json', '/api/v1/test/pub/http') };
    $data = decode_json $stdout;
    is $data->{method}, 'POST', 'POST request';
    is $data->{headers}{'Accept'}, 'application/json', 'Accept header';
};

subtest 'PIPE input' => sub {
    my $file = tempfile;
    my $fh   = $file->spurt('Hello openQA!')->open('<');
    local *STDIN = $fh;
    my ($stdout, @result) = capture_stdout sub { $api->run(@host, '/api/v1/test/pub/http') };
    my $data = decode_json $stdout;
    is $data->{body}, 'Hello openQA!', 'request body';
};

done_testing();
