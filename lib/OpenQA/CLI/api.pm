# Copyright (C) 2020 SUSE LLC
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

package OpenQA::CLI::api;
use Mojo::Base 'OpenQA::Command';

use Mojo::File 'path';
use Mojo::JSON qw(decode_json);
use Mojo::URL;
use Mojo::Util qw(decode getopt);

has description => 'Issue an arbitrary request to the API';
has usage       => sub { shift->extract_usage };

sub run {
    my ($self, @args) = @_;

    my $data = $self->data_from_stdin;

    getopt \@args,
      'a|header=s'    => \my @headers,
      'apibase=s'     => \(my $base = '/api/v1'),
      'apikey=s'      => \my $key,
      'apisecret=s'   => \my $secret,
      'D|data-file=s' => \my $data_file,
      'd|data=s'      => \$data,
      'f|form'        => \my $form,
      'H|host=s'      => \(my $host = 'http://localhost'),
      'j|json'        => \my $json,
      'p|pretty'      => \my $pretty,
      'q|quiet'       => \my $quiet,
      'X|method=s'    => \(my $method = 'GET');

    @args = map { decode 'UTF-8', $_ } @args;

    die $self->usage unless my $path = shift @args;
    my $url = Mojo::URL->new($host);
    $url->path($self->prepend_apibase($base, $path));

    $data = path($data_file)->slurp if $data_file;
    my @data   = ($data);
    my $params = $form ? decode_json($data) : $self->parse_params(@args);
    @data = (form => $params) if keys %$params;

    my $headers = $self->parse_headers(@headers);
    $headers->{Accept} //= 'application/json';
    $headers->{'Content-Type'} = 'application/json' if $json;

    my $client = $self->client(apikey => $key, apisecret => $secret, api => $url->host);
    my $tx     = $client->build_tx($method, $url, $headers, @data);
    $tx = $client->start($tx);
    $self->handle_result($tx, {pretty => $pretty, quiet => $quiet});
}

1;

=encoding utf8

=head1 SYNOPSIS

  Usage: openqa-cli api [OPTIONS] PATH [PARAMS]

    openqa-cli api -H https://openqa.opensuse.org job_templates_scheduling/24

  Options:
        --apibase <path>        API base, defaults to /api/v1
        --apikey <key>          API key
        --apisecret <secret>    API secret
    -a, --header <name:value>   One or more additional HTTP headers
    -D, --data-file <path>      Load content to send with request from file
    -d, --data <string>         Content to send with request, alternatively you
                                can also pipe data to openqa-cli
    -f, --form                  Turn JSON object into form parameters
    -H, --host <host>           Target host, defaults to http://localhost
    -h, --help                  Show this summary of available options
    -j, --json                  Request content is JSON
    -p, --pretty                Pretty print JSON content
    -q, --quiet                 Do not print error messages to STDERR
    -X, --method <method>       HTTP method to use, defaults to GET

=cut
