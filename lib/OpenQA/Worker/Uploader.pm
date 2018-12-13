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

package OpenQA::Worker::Uploader;

use strict;
use warnings;

use Mojo::Base -base;

sub new {
    shift->SUPER::new(@_)->init;
}

sub from_worker {
    my ($worker_settings, undef) = OpenQA::Worker::Common::read_worker_config(undef, undef);
    __PACKAGE__->new(host     => 'localhost');
}

sub DESTROY {
    my $self = shift;

}

sub upload_results {
    # TODO: add image upload stuff which is currently in Jobs.pm here
}


1;
