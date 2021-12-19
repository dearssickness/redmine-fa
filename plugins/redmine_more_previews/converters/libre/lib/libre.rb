# encoding: utf-8
#
# RedmineMorePreviews converter to preview office files with LibreOffice
#
# Copyright © 2020 Stephan Wenzel <stephan.wenzel@drwpatent.de>
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

class Libre < RedmineMorePreviews::Conversion

  #---------------------------------------------------------------------------------
  # constants
  #---------------------------------------------------------------------------------
  LIBRE_OFFICE_BIN = 'soffice'.freeze
  
  #---------------------------------------------------------------------------------
  # check: is LibreOffice available?
  #---------------------------------------------------------------------------------
  def status
    s = run [LIBRE_OFFICE_BIN, "--version"]
    [:text_libre_office_available, s[2] == 0 ]
  end
  
  def convert
    
    Dir.mktmpdir do |tdir| 
    user_installation = File.join(tdir, "user_installation")
    command(cd + join + soffice( source, user_installation ) + join + move(thisdir(outfile)) )
    end
    
  end #def
  
  def soffice( src, user_installation )
    "#{LIBRE_OFFICE_BIN} --headless --convert-to #{preview_format} --outdir #{shell_quote tmpdir} -env:UserInstallation=file://#{user_installation} #{shell_quote src}"
  end #def
  
end #class