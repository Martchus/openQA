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

package OpenQA::Task::Screenshot::PopulateLinkCount;
use Mojo::Base 'Mojolicious::Plugin';

use OpenQA::Utils;
use Mojo::URL;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(populate_screenshot_link_count => sub { _populate_screenshot_link_count($app, @_) });
}

sub _populate_screenshot_link_count {
    my ($app, $job) = @_;

    my $schema = $app->schema;
    $schema->storage->dbh->prepare(
'UPDATE screenshots SET link_count=subquery.link_count FROM (SELECT screenshot_id, count(screenshot_id) AS link_count FROM screenshot_links GROUP BY screenshot_id) AS subquery WHERE screenshots.id=subquery.screenshot_id'
    )->execute;
}

1;
