# Copyright 2018-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::CacheService;
use Mojo::Base 'Mojolicious', -signatures;

use Mojo::SQLite;
use Mojo::File 'path';
use OpenQA::Worker::Settings;
use OpenQA::CacheService::Model::Cache;
use OpenQA::CacheService::Model::Downloads;

use constant DEFAULT_MINION_WORKERS => 5;

# Default to 10 minutes
use constant SQLITE_BUSY_TIMEOUT => $ENV{OPENQA_SQLITE_BUSY_TIMEOUT} // 600000;

# Defaults to 1 minute
use constant SQLITE_SLOW_QUERY => $ENV{OPENQA_SQLITE_SLOW_QUERY} // 60000;

has exit_code => undef;

sub _configure_sqlite_database ($self, $sqlite, $dbh) {
    # default to using DELETE journaling mode to avoid database corruption seen in production (see poo#67000)
    # checkout https://www.sqlite.org/pragma.html#pragma_journal_mode for possible values
    my $sqlite_mode = uc($ENV{OPENQA_CACHE_SERVICE_SQLITE_JOURNAL_MODE} || 'DELETE');
    $dbh->sqlite_busy_timeout(SQLITE_BUSY_TIMEOUT);
    $dbh->do("pragma journal_mode=$sqlite_mode");
    $dbh->do('pragma synchronous=NORMAL') if $sqlite_mode eq 'WAL';

    # Log slow queries
    $dbh->sqlite_profile(
        sub ($statement, $elapsed, @) {
            $self->log->info(qq{Slow SQLite query: "$statement" -> ${elapsed}ms}) if $elapsed > SQLITE_SLOW_QUERY;
        });
}

sub _open_sqlite_database ($self, $db_file) {
    my $sqlite = Mojo::SQLite->new->from_string("file://$db_file?no_wal=1");
    $sqlite->on(connection => sub ($sqlite, $dbh) { $self->_configure_sqlite_database($sqlite, $dbh) });
    return $sqlite;
}

sub startup {
    my $self = shift;

    $self->defaults(appname => 'openQA Cache Service');
    # Provide help to users early to prevent failing later on
    # misconfigurations
    return $self->exit_code(0) if $ENV{MOJO_HELP};

    # Stop the service after a critical database error
    my $code = $self->renderer->get_helper('reply.exception');
    $self->helper(
        'reply.exception' => sub {
            my ($c, $error) = @_;
            $error = $c->$code($error)->stash('exception');
            return unless $error =~ qr/(database disk image is malformed|no such (table|column))/;

            my $app = $c->app;
            $app->exit_code(1);    # ensure the return code is non-zero
            $app->log->error('Stopping service after critical database error');
            Mojo::IOLoop->singleton->stop_gracefully;
            # stop server manager used in prefork mode
            my $service_pid = $c->stash('service_pid');
            kill QUIT => $service_pid if defined $service_pid && $service_pid != $$;
        });

    # Worker settings
    my $global_settings = OpenQA::Worker::Settings->new->global_settings;
    my $location = $ENV{OPENQA_CACHE_DIR} || $global_settings->{CACHEDIRECTORY};
    die "Cache directory unspecified. Set environment variable 'OPENQA_CACHE_DIR' or config variable 'CACHEDIRECTORY'\n"
      unless defined $location;
    my $limit = $global_settings->{CACHELIMIT};
    my $min_free_percentage = $global_settings->{CACHE_MIN_FREE_PERCENTAGE};

    # commands
    push @{$self->commands->namespaces}, 'OpenQA::CacheService::Command';

    # Allow for very quiet tests
    $self->hook(
        before_server_start => sub {
            my ($server, $app) = @_;
            $server->silent(1) if $app->mode eq 'test';
        });
    my $log = $self->log;
    $log->unsubscribe('message') if $ENV{OPENQA_CACHE_SERVICE_QUIET};

    # Increase busy timeout to 5 minutes
    my $sqlite = $self->_open_sqlite_database(path($location, 'cache.sqlite'));
    $sqlite->migrations->name('cache_service')->from_data;

    my @cache_params = (sqlite => $sqlite, log => $self->log, location => $location);
    push @cache_params, limit => int($limit) * (1024**3) if defined $limit;
    push @cache_params, min_free_percentage => $min_free_percentage if defined $min_free_percentage;
    $self->helper(cache => sub { state $cache = OpenQA::CacheService::Model::Cache->new(@cache_params) });
    my $cache = $self->cache;
    $self->helper(downloads => sub { state $dl = OpenQA::CacheService::Model::Downloads->new(cache => $cache) });
    $cache->init;

    $self->plugin(Minion => {SQLite => $sqlite});
    $self->plugin('Minion::Admin');
    $self->plugin('OpenQA::CacheService::Task::Asset');
    $self->plugin('OpenQA::CacheService::Task::Sync');
    $self->plugin('OpenQA::CacheService::Plugin::Helpers');

    my $r = $self->routes;
    $r->get('/' => sub { shift->redirect_to('/minion') });
    $r->get('/info')->to('API#info');
    $r->get('/status/<id:num>')->to('API#status');
    $r->put('/withdraw/<id:num>')->to('API#withdraw');
    $r->post('/enqueue')->to('API#enqueue');
    $r->get('/influxdb/minion')->to('Influxdb#minion');
    $r->any('/*whatever' => {whatever => ''})->to(status => 404, text => 'Not found');
}

sub setup_workers {
    return @_ unless grep { $_ eq 'run' } @_;
    my @args = @_;

    my $global_settings = OpenQA::Worker::Settings->new->global_settings;
    my $cache_workers
      = exists $global_settings->{CACHEWORKERS} ? $global_settings->{CACHEWORKERS} : DEFAULT_MINION_WORKERS;
    push @args, '-j', $cache_workers;

    return @args;
}

sub run {
    my @args = setup_workers(@_);

    local $ENV{MOJO_LOG_SHORT} = 1;
    my $app = __PACKAGE__->new;
    $ENV{MOJO_INACTIVITY_TIMEOUT} //= 300;
    $app->log->debug("Starting cache service: $0 @args");
    $app->defaults->{service_pid} = $$;

    my $cmd_return_code = $app->start(@args);
    return $app->exit_code // $cmd_return_code // 0;
}

1;

=encoding utf-8

=head1 NAME

OpenQA::CacheService - OpenQA Cache Service

=head1 SYNOPSIS

    use OpenQA::CacheService;

    # Start the daemon
    OpenQA::CacheService::run(qw(daemon));

    # Start one or more Minions
    OpenQA::CacheService::run(qw(run))

=head1 DESCRIPTION

OpenQA::CacheService is the OpenQA Cache Service, which is meant to be run
standalone.

=head1 GET ROUTES

OpenQA::CacheService is a L<Mojolicious::Lite> application, and it is exposing the following GET routes.

=head2 /minion

Redirects to the L<Mojolicious::Plugin::Minion::Admin> Dashboard.

=head2 /info

Returns Minon statistics, see L<https://metacpan.org/pod/Minion#stats>.

=head2 /status/<id>

Retrieve current job status in JSON format.

=head2 /influxdb/minion

Minion job queue statistics in InfluxDB format for easy monitoring.

=head1 POST ROUTES

OpenQA::CacheService is exposing the following POST routes.

=head2 /enqueue

Enqueue the task. It acceps a POST JSON payload of the form:

      {task => 'cache_assets', args => [qw(42 test hdd open.qa)], lock => 'some lock'}

=cut

__DATA__
@@ cache_service
-- 1 up
CREATE TABLE IF NOT EXISTS assets (
    `etag` TEXT,
    `size` INTEGER,
    `last_use` DATETIME NOT NULL,
    `filename` TEXT NOT NULL UNIQUE,
    PRIMARY KEY(`filename`)
);

-- 1 down
DROP TABLE assets;

-- 2 up
CREATE TABLE IF NOT EXISTS downloads (
    `id` INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    `lock` TEXT,
    `job_id` TEXT,
    `created` DATETIME NOT NULL DEFAULT current_timestamp
);
CREATE INDEX IF NOT EXISTS downloads_lock on downloads (lock);
CREATE INDEX IF NOT EXISTS downloads_created on downloads (created);

-- 2 down
DROP TABLE downloads;

-- 3 up
ALTER TABLE assets ADD COLUMN `pending` INTEGER DEFAULT 1;

-- 4 up
CREATE INDEX IF NOT EXISTS assets_pending on assets (pending);

-- 5 up
CREATE TABLE IF NOT EXISTS metrics (
    `name` TEXT NOT NULL UNIQUE,
    `value` TEXT,
    PRIMARY KEY(`name`)
);

-- 5 down
DROP TABLE metrics;
