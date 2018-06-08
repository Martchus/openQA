# Copyright (C) 2018 SUSE LLC
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

package OpenQA::Test::FakeWebSocketTransaction;

use strict;
use Mojo::Base -base;

has(finish_called => 0);
has(sent_messages => sub { return []; });

sub clear_messages {
    my ($self) = @_;
    $self->sent_messages([]);
}

sub is_websocket {
    my ($self) = @_;
    return 1;
}

sub send {
    my ($self, $message) = @_;
    push(@{$self->sent_messages}, $message);
    return 1;
}

sub finish {
    my ($self) = @_;
    $self->finish_called(1);
    return 1;
}

1;
