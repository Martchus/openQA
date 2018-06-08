package OpenQA::SeleniumTest;
use base 'Exporter';

use Mojo::IOLoop::Server;
use strict;

# Start command line interface for application
require Mojolicious::Commands;
require OpenQA::Test::Database;

our @EXPORT = qw($drivermissing check_driver_modules
  start_driver call_driver kill_driver kill_specific_driver
  wait_for_ajax javascript_console_has_no_warnings_or_errors);

use Data::Dump 'pp';
use Test::More;
use Try::Tiny;
use Time::HiRes 'time';

our $_driver;
our $mojopid;
our $mojoport;
our $startingpid   = 0;
our $drivermissing = 'Install Selenium::Remote::Driver and Selenium::Chrome to run these tests';

=head2 start_app

  start_app([$schema_hook]);

Fork a server instance with database creation and return the server port.

By default the database is created based on the fixture set.

The optional parameter C<$schema_hook> allows to provide a custom way of creating a database, e.g.

    sub schema_hook {
        my $schema = OpenQA::Test::Database->new->create;
        # delete unused job id 1234
        $schema->resultset('Jobs')->find(1234)->delete;
    }
    start_app(\&schema_hook);
=cut

sub start_app {
    my ($schema_hook) = @_;
    $mojoport = $ENV{MOJO_PORT} // Mojo::IOLoop::Server->generate_port;

    $startingpid = $$;
    $mojopid     = fork();
    if ($mojopid == 0) {
        if ($schema_hook) {
            $schema_hook->();
        }
        else {
            OpenQA::Test::Database->new->create;
        }

        # TODO: start the server manually - and make it silent
        # Run openQA in test mode - it will mock Scheduler and Websockets DBus services
        $ENV{MOJO_MODE}   = 'test';
        $ENV{MOJO_LISTEN} = "127.0.0.1:$mojoport";
        Mojolicious::Commands->start_app('OpenQA::WebAPI', 'daemon', '-l', "http://127.0.0.1:$mojoport/");
        exit(0);
    }
    else {
        #$SIG{__DIE__} = sub { kill('TERM', $mojopid); };
        # as this might download assets on first test, we need to wait a while
        my $wait = time + 50;
        while (time < $wait) {
            my $t      = time;
            my $socket = IO::Socket::INET->new(
                PeerHost => '127.0.0.1',
                PeerPort => $mojoport,
                Proto    => 'tcp',
            );
            last if $socket;
            sleep 1 if time - $t < 1;
        }
    }
    return $mojoport;
}

sub start_driver {
    my ($mojoport, $custom_port) = @_;

    # Connect to it
    my $driver;
    #eval {
    my %opts = (
        base_url           => "http://localhost:$mojoport/",
        default_finder     => 'css',
        webelement_class   => 'Test::Selenium::Remote::WebElement',
        extra_capabilities => {
            loggingPrefs  => {browser => 'ALL'},
            chromeOptions => {args    => []}
        },
    );

    # chromedriver is unfortunately hidden on openSUSE
    my @chromiumdirs = qw(/usr/lib64/chromium);
    for my $dir (@chromiumdirs) {
        if (-d $dir) {
            $ENV{PATH} = "$ENV{PATH}:$dir";
        }
    }
    my $suffix = $custom_port ? '-' . $custom_port : '';
    $opts{custom_args} = "--log-path=t/log_chromedriver$suffix";
    $opts{port} = $custom_port if ($custom_port);
    unless ($ENV{NOT_HEADLESS}) {
        push(@{$opts{extra_capabilities}{chromeOptions}{args}}, ('--headless', '--disable-gpu'));
    }

    print("Starting Selenium::Chrome: $suffix\n");
    if ($suffix) {
        sleep 3.5;
    }
    $driver = Test::Selenium::Chrome->new(%opts);
    $driver->set_implicit_wait_timeout(2000);
    $driver->set_window_size(600, 800);
    $driver->get("http://localhost:$mojoport/");

    # use the first driver we start by default in functions like make_screenshot()
    $_driver //= $driver;
    #};
    #die $@ if ($@);

    return $_driver;
}

sub make_screenshot($) {
    my ($fn, $driver) = (@_);
    $driver //= $_driver;

    open(my $fh, '>', $fn);
    binmode($fh);
    my $png_base64 = $driver->screenshot();
    print($fh MIME::Base64::decode_base64($png_base64));
    close($fh);
}

sub check_driver_modules {

    # load required modules if possible. DO NOT EVER PUT THESE IN
    # 'use' FUNCTION CALLS! Always use can_load! Otherwise you will
    # break the case where they are not available and tests should
    # be skipped.
    use Module::Load::Conditional qw(can_load);
    return can_load(
        modules => {
            'Test::Selenium::Chrome'   => '1.20',
            'Selenium::Remote::Driver' => undef,
        });
}

sub call_driver {

    # return a omjs driver using specified schema hook if modules
    # are available, otherwise return undef
    return unless check_driver_modules;
    my ($schema_hook) = @_;
    my $mojoport = start_app($schema_hook);
    return start_driver($mojoport);
}

sub _default_check_interval {
    return shift // 0.25;
}

sub wait_for_ajax {
    my ($check_interval, $driver) = @_;
    $check_interval = _default_check_interval($check_interval);
    $driver //= $_driver;
    while (!$driver->execute_script("return jQuery.active == 0")) {
        sleep $check_interval;
    }
}

sub javascript_console_has_no_warnings_or_errors {
    my ($test_name_suffix, $driver) = @_;
    $test_name_suffix //= '';
    $driver //= $_driver;

    my $log = $driver->get_log('browser');
    my @errors;
    for my $log_entry (@$log) {
        my $level = $log_entry->{level};
        if ($level eq 'DEBUG' or $level eq 'INFO') {
            next;
        }

        my $source = $log_entry->{source};
        my $msg    = $log_entry->{message};
        if ($source eq 'network') {
            # ignore errors when gravatar not found
            next if ($msg =~ m,/gravatar/,);
            # FIXME: loading thumbs during live run causes 404. ignore for now
            next if ($msg =~ m,/thumb/, || $msg =~ m,/.thumbs/,);
        }
        elsif ($source eq 'javascript') {
            # FIXME: ignore WebSocket error for now (connection errors are tracked via devel console anyways)
            next if ($msg =~ m/ws\-proxy.*Close received/);
        }
        push(@errors, $log_entry);
    }

    diag('javascript console output: ' . pp(\@errors)) if @errors;
    is_deeply(\@errors, [], 'no errors or warnings on javascript console' . $test_name_suffix);
}

# kills the first driver instance and the Mojolicious server
sub kill_driver() {
    return unless $startingpid && $$ == $startingpid;
    if ($_driver) {
        $_driver->quit();
        $_driver->shutdown_binary;
        $_driver = undef;
    }
    if ($mojopid) {
        kill('TERM', $mojopid);
        waitpid($mojopid, 0);
        $mojopid = undef;
    }
}

# kills the specified driver; used to kill secondary driver instance
sub kill_specific_driver {
    my ($driver) = @_;
    return unless ($driver);
    $driver->quit();
    $driver->shutdown_binary();
}

sub get_mojoport {
    return $mojoport;
}

END {
    kill_driver;
}

1;
