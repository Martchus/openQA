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
# with this program; if not, see <http://www.gnu.org/licenses/>.

package OpenQA::WebAPI::Controller::API::V1::AuditEvent;
use Mojo::Base 'Mojolicious::Controller';

=pod

=head1 NAME

OpenQA::WebAPI::Controller::API::V1::AuditEvent

=head1 SYNOPSIS

  use OpenQA::WebAPI::Controller::API::V1::AuditEvent;

=head1 DESCRIPTION

OpenQA API implementation for audit events.

=cut

sub trigger_cleanup {
    my ($self) = @_;

    my $ids = $self->gru->enqueue('limit_audit_events');
    $self->render(
        json => {
            gru_task_id   => $ids->{gru_id},
            minion_job_id => $ids->{minion_id},
        });
}

1;
# vim: set sw=4 et:
