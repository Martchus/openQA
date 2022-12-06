# Copyright 2019 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Worker::Settings;
use Mojo::Base -base, -signatures;

use Mojo::Util 'trim';
use Config::IniFiles;
use Time::Seconds;
use OpenQA::Log 'setup_log';
use Net::Domain 'hostfqdn';

has 'global_settings';
has 'webui_hosts';
has 'webui_host_specific_settings';

sub new ($class, $instance_number = undef, $cli_options = {}) {
    my $settings_file = ($ENV{OPENQA_CONFIG} || '/etc/openqa') . '/workers.ini';
    my $cfg;
    my @parse_errors;
    if (-e $settings_file) {
        $cfg = Config::IniFiles->new(-file => $settings_file);
        push(@parse_errors, @Config::IniFiles::errors) unless $cfg;
    }
    else {
        push(@parse_errors, "Config file not found at '$settings_file'.");
        $settings_file = undef;
    }

    # read global settings from config
    my %global_settings;
    for my $section ('global', $instance_number) {
        if ($cfg && $cfg->SectionExists($section)) {
            for my $set ($cfg->Parameters($section)) {
                $global_settings{uc $set} = trim $cfg->val($section, $set);
            }
        }
    }

    # read global settings from environment variables
    for my $var (qw(LOG_DIR TERMINATE_AFTER_JOBS_DONE)) {
        $global_settings{$var} = $ENV{"OPENQA_WORKER_$var"} if ($ENV{"OPENQA_WORKER_$var"} // '') ne '';
    }

    # read global settings specified via CLI arguments
    $global_settings{LOG_LEVEL} = 'debug' if $cli_options->{verbose};

    # determine web UI host
    my $webui_host = $cli_options->{host} || $global_settings{HOST} || 'localhost';
    delete $global_settings{HOST};

    # determine web UI host specific settings
    my %webui_host_specific_settings;
    my @hosts = split(' ', $webui_host);
    for my $section (@hosts) {
        if ($cfg && $cfg->SectionExists($section)) {
            for my $set ($cfg->Parameters($section)) {
                $webui_host_specific_settings{$section}->{uc $set} = trim $cfg->val($section, $set);
            }
        }
        else {
            $webui_host_specific_settings{$section} = {};
        }
    }

    # set some environment variables
    # TODO: This should be sent to the scheduler to be included in the worker's table.
    if (defined $instance_number) {
        $ENV{QEMUPORT} = $instance_number * 10 + 20002;
        $ENV{VNC} = $instance_number + 90;
    }

    # assign default retry-delay for web UI connection
    $global_settings{RETRY_DELAY} //= 5;
    $global_settings{RETRY_DELAY_IF_WEBUI_BUSY} //= ONE_MINUTE;

    my $self = $class->SUPER::new(
        global_settings => \%global_settings,
        webui_hosts => \@hosts,
        webui_host_specific_settings => \%webui_host_specific_settings,
    );
    $self->{_file_path} = $settings_file;
    $self->{_parse_errors} = \@parse_errors;
    return $self;
}

sub auto_detect_worker_address ($self, $fallback = undef) {
    my $global_settings = $self->global_settings;
    my $current_address = $global_settings->{WORKER_HOSTNAME};
    my $required = ($self->{_worker_address_required} ||= defined $current_address && $current_address eq 'auto');

    # skip auto-detection and ignore missing WORKER_HOSTNAME unless WORKER_HOSTNAME is "auto"
    # skip auto-detection if WORKER_HOSTNAME is set explicitly to something other than "auto"
    return 1 if !$required || (defined $current_address && !$required && !$self->{_worker_address_auto_detected});

    # do auto-detection which is considered successful if hostfqdn() returns something with a dot in it
    $self->{_worker_address_auto_detected} = 1;
    my $worker_address = hostfqdn() // $fallback;
    $global_settings->{WORKER_HOSTNAME} = $worker_address if defined $worker_address;
    return defined $worker_address && index($worker_address, '.') >= 0;
}

sub apply_to_app ($self, $app) {
    my $global_settings = $self->global_settings;
    $app->log_dir($global_settings->{LOG_DIR});
    $app->level($global_settings->{LOG_LEVEL}) if $global_settings->{LOG_LEVEL};
    setup_log($app, undef, $app->log_dir, $app->level);
}

sub file_path ($self) { $self->{_file_path} }

sub parse_errors ($self) { $self->{_parse_errors} }

1;
