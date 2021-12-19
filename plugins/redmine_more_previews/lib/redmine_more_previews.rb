# encoding: utf-8
# frozen_string_literal: true

# Redmine plugin to preview various file types in redmine's preview pane
#
# Copyright © 2018 -2020 Stephan Wenzel <stephan.wenzel@drwpatent.de>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#



# helpers (loa before controller patches)
require 'redmine_more_previews/lib/controller_helper'

# patches
require 'redmine_more_previews/patches/entry_patch'
require 'redmine_more_previews/patches/mime_type_patch'
require 'redmine_more_previews/patches/repository_patch'
require 'redmine_more_previews/patches/attachment_patch'
require 'redmine_more_previews/patches/admin_controller_patch'
require 'redmine_more_previews/patches/application_helper_patch'
require 'redmine_more_previews/patches/attachments_controller_patch'
require 'redmine_more_previews/patches/repositories_controller_patch'

# libraries
require 'redmine_more_previews/lib/rmp_file'
require 'redmine_more_previews/lib/rmp_img'
require 'redmine_more_previews/lib/rmp_pdf'
require 'redmine_more_previews/lib/rmp_shell'
require 'redmine_more_previews/lib/exceptions'

# workers
require 'redmine_more_previews/lib/converter'
require 'redmine_more_previews/lib/conversion'

