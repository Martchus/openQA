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

package OpenQA::Worker::Cache::Request::Upload;
use Mojo::Base 'OpenQA::Worker::Cache::Request';

# see task OpenQA::Cache::Task::Upload
has [qw(id job)];
has task => 'upload_results';

sub lock {
    my ($self) = @_;
    return $job->{id};
}

sub to_hash {
    my ($self) = @_;

    return {
        id  => $self->id,
        job => $self->job,
    };
}
sub to_array {
    my ($self) = @_;

    return [
        id  => $self->id,
        job => $self->job,
    ];
}

1;
