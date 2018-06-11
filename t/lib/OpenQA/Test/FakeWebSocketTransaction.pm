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
use Test::MockModule;
use Mojo::Base -base;

has(finish_called => 0);
has(sent_messages => sub { return []; });
has(mocked_modules => sub { return []; });

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

sub mock_modules {
    my ($self, $module_names) = @_;

    for my $module_name (@$module_names) {
        print("mocking $module_name\n");
        #my $mock_module = new Test::MockModule($module_name);
        my $mock_module = new Test::MockModule('Mojo::Transaction::WebSocket');
        #$mock_module->mock(new => sub {
        #    print("custom c'tor called\n");
        #    return $self;
        #});
        $mock_module->mock(is_websocket => sub {
            print("custom is_websocket called\n");
            return $self->is_websocket();
        });
        $mock_module->mock(send => sub {
            my ($mock_module, $message) = @_;
            print("custom send called\n");
            return $self->send($message);
        });
        $mock_module->mock(finish => sub {
            print("custom finish called\n");
            return $self->finish();
        });
        push(@{$self->mocked_modules}, $mock_module);
    }
}

sub mock_ws_connection {
    my ($self) = @_;
    return $self->mock_modules(['Mojo::Transaction::WebSocket']);
}

sub unmock_modules {
    my ($self) = @_;

    print("unmocking modules again\n");

    for my $mock_module (@{$self->mocked_modules}) {
        $mock_module->unmock_all();
    }
    $self->mocked_modules([]);
}

1;
