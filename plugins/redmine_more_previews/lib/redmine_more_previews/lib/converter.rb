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

require 'mimemagic'
require 'mimemagic/overlay'

module RedmineMorePreviews
  
  ########################################################################################
  #
  # Exceptions
  #
  ########################################################################################
  # Exception raised when a converter cannot be found given its id.
  class ConverterNotFound < StandardError; end
  
  # Exception raised when a converter requirement is not met.
  class ConverterRequirementError < StandardError; end
  
  # Base class for Converters.
  # Converters are registered using the <tt>register</tt> class method that acts as the public constructor.
  #
  #   RedmineMorePreviews::Converter.register :textmate do
  #     name 'Example text to html converter'
  #     author 'John Smith'
  #     description 'This is an example converter for RedmineMorePreviews'
  #     version '0.0.1'
  #     settings :default => {'foo'=>'bar'}, :partial => 'settings/settings'
  #     class_name 'Textmate'
  #     mime_types(:txt => {:formats => [:html], :mime => 'text/plain'})
  #   end
  #
  # === Converter attributes
  #
  # +settings+ is an optional attribute that let the converter be configurable.
  # It must be a hash with the following keys:
  # * <tt>:default</tt>: default value for the plugin settings
  # Example:
  #   settings :default => {'foo'=>'bar'}
  #
  class Converter
  
    ######################################################################################
    #
    # constants
    #
    ######################################################################################
    FORMATS      = %i(html inline txt pdf png jpg gif xml)
    FORMAT_MIMES = {"html" => "text/html",  "inline" => "text/html", 
                    "txt"  => "text/plain", "pdf"    => "application/pdf", 
                    "png"  => "image/png",  "jpg"    => "image/jpeg",
                    "gif"  => "image/gif",  "xml"    => "text/xml" }
    
    ######################################################################################
    #
    # variables
    #
    ######################################################################################
    cattr_accessor :directory
    self.directory = File.join(Redmine::Plugin.find(:redmine_more_previews).directory, "converters")
    
    # absolute path to the public directory where converter plugins assets are copied
    cattr_accessor :public_directory
    self.public_directory = File.join(Redmine::Plugin.public_directory, "redmine_more_previews", "converters")
    
    @registered_converters = {}
    @used_partials = {}
    
    ######################################################################################
    #
    # fields
    #
    ######################################################################################
    class << self
    
      attr_reader :registered_converters
      private :new
      
      def def_field(*names)
        class_eval do
          names.each do |name|
            define_method(name) do |*args|
              args.empty? ? instance_variable_get("@#{name}") : instance_variable_set("@#{name}", *args)
            end
          end
        end
      end #def
    end #class
    def_field(:name, :class_name, :threadsafe, :description, :directory, 
              :timeout, :shell_api, :url, :author, :author_url, :version)
    attr_reader :id
    attr_accessor :mime_types, :converter_class, :semaphore
    
    ######################################################################################
    #
    # class functions
    #
    ######################################################################################
    def self.register(id, &block)
      c = new(id)
      c.instance_eval(&block)
      
      # Set a default name if it was not provided during registration
      c.name(id.to_s.humanize) if c.name.nil?
      # Set a default class if it was not provided during registration
      c.class_name(id.to_s.classify) if c.class_name.nil?
      # Set a default directory if it was not provided during registration
      c.directory(File.join(self.directory, id.to_s)) if c.directory.nil?
      # create a semaphore unless threadsafe
      c.threadsafe(false) if c.threadsafe.nil?
      # create a timeout value for shell execution
      c.timeout(5) if c.timeout.nil?
      # create a shell_api
      c.shell_api("open3") if c.shell_api.nil?
      
      unless File.directory?(c.directory)
        raise ConverterNotFound, "Converter not found. The directory for converter #{c.id} should be #{c.directory}."
      end
      
      # Adds plugin locales if any
      # YAML translation files should be found under <plugin>/config/locales/
      Rails.application.config.i18n.load_path += Dir.glob(File.join(c.directory, 'config', 'locales', '*.yml'))
      
      # Prepends the app/views directory of the plugin to the view path
      view_path = File.join(c.directory, 'app', 'views')
      if File.directory?(view_path)
        ActionController::Base.prepend_view_path(view_path)
        ActionMailer::Base.prepend_view_path(view_path)
      end
      
      # Add the plugin directories to rails autoload paths
      engine_cfg = Rails::Engine::Configuration.new(c.directory)
      engine_cfg.paths.add 'lib', eager_load: true
      Rails.application.config.eager_load_paths += engine_cfg.eager_load_paths
      Rails.application.config.autoload_once_paths += engine_cfg.autoload_once_paths
      Rails.application.config.autoload_paths += engine_cfg.autoload_paths
      ActiveSupport::Dependencies.autoload_paths += engine_cfg.eager_load_paths + engine_cfg.autoload_once_paths + engine_cfg.autoload_paths
      
      # Warn for potential settings[:partial] collisions
      if c.configurable?
        partial = c.settings[:partial]
        if @used_partials[partial]
          Rails.logger.warn "WARNING: cnverter settings partial '#{partial}' is declared in '#{c.id}' converter but it is already used by converter '#{@used_partials[partial]}'. Only one settings view will be used. You may want to contact those converter authors to fix this."
        end
        @used_partials[partial] = c.id
      end
      
      # create instance of the actual converter
      c.converter_class = c.class_name.constantize # rescue nil
      
      # create a semaphore even for threadsafe converters
      c.semaphore = Mutex.new
      
      # register mime type, unless already registered
      c.mime_types.each do |key, val|
        unless Mime::Type.lookup_by_extension(key.to_s)
          Mime::Type.register(val[:mime], key, val[:synonyms].to_a)
        end
      end if c.mime_types.is_a?(Hash)
      
      # copy converter assets to plugin 'redmine_moore_previews' directory
      c.mirror_assets
      
      registered_converters[id] = c
    end #def
    
    # Returns an array of all registered converters
    def self.all
      registered_converters.values.sort
    end
    
    # Finds a converter by its id
    # Returns a ConverterNotFound exception if the converter doesn't exist
    def self.find(id)
      registered_converters[id.to_sym] || raise(ConverterNotFound)
    end
    
    # Clears the registered converters hash
    # It doesn't unload installed converters
    def self.clear
      @registered_converters = {}
    end
    
    # Removes a converter from the registered converters
    # It doesn't unload the converter
    def self.unregister(id)
      @registered_converters.delete(id)
    end
    
    # Checks if a converter is installed
    #
    # @param [String] id name of the converter
    def self.installed?(id)
      registered_converters[id.to_sym].present?
    end
    
    # Checks if converter is configurable
    #
    # Returns +true+ if the converter can be configured.
    def configurable?
      settings.is_a?(Hash) && settings[:partial].present?
    end
    
    # Loads the converters
    #
    #
    def self.load
      Dir.glob(File.join(self.directory, '*')).sort.each do |directory|
        if File.directory?(directory)
          lib = File.join(directory, "lib")
          if File.directory?(lib)
            $:.unshift lib
            ActiveSupport::Dependencies.autoload_paths += [lib]
          end
          initializer = File.join(directory, "init.rb")
          if File.file?(initializer)
            require initializer
          end
        end
      end
    end
    
    # Copies converter assets to public directory
    #
    def mirror_assets
      source = assets_directory
      destination = public_directory
      return unless File.directory?(source)
      
      source_files = Dir[source + "/**/*"]
      source_dirs = source_files.select { |d| File.directory?(d) }
      source_files -= source_dirs
      
      unless source_files.empty?
        base_target_dir = File.join(destination, File.dirname(source_files.first).gsub(source, ''))
        begin
          FileUtils.mkdir_p(base_target_dir)
        rescue => e
          raise "Could not create directory #{base_target_dir}: " + e.message
        end
      end
      
      source_dirs.each do |dir|
        # strip down these paths so we have simple, relative paths we can
        # add to the destination
        target_dir = File.join(destination, dir.gsub(source, ''))
        begin
          FileUtils.mkdir_p(target_dir)
        rescue => e
          raise "Could not create directory #{target_dir}: " + e.message
        end
      end
      
      source_files.each do |file|
        begin
          target = File.join(destination, file.gsub(source, ''))
          unless File.exist?(target) && FileUtils.identical?(file, target)
            FileUtils.cp(file, target)
          end
        rescue => e
          raise "Could not copy #{file} to #{target}: " + e.message
        end
      end
    end
    
    ######################################################################################
    #
    # convert functions
    #
    ######################################################################################
    def self.convertible?( filename )
      ext = File.extname( filename ).gsub(/\A\./,"").downcase
      active_extensions.include?(ext)
    end #def
    
    def self.cache_previews?
      ::Setting['plugin_redmine_more_previews']['cache_previews'].to_i > 0
    end #def
    
    def self.embed?
      ::Setting['plugin_redmine_more_previews']['embedding'].to_i == 0
    end #def
    
    def self.mime( filepath, options={} )
    
      unless options[:pathonly]
      # try by file content
      mime_type = nil; File.open( filepath ) {|f| mime_type = MimeMagic.by_magic(f).try(:type) }
      mime      = active_mime_types.select{|m,opts| mime_type == opts["mime"] }.values.first if mime_type
      return mime if mime
      end
      
      # try by file extension
      ext       = File.extname( filepath.downcase ).gsub(/\A\./,"")
      mime      = active_mime_types[ext] if ext.present?
      return mime if mime
      
      # give up
      raise ConverterNotFound
    end #def
    
    def self.conversion_mime( filepath, options={} )
      FORMAT_MIMES[mime( filepath, options )["format"]].presence || "application/octet-stream"
    end #def
    
    def self.conversion_ext( filepath, options={} )
      mime( filepath, options )["format"]
    end #def
    
    def self.responsible( file, options={} )
      find(mime( file, options )["converter"]) rescue nil
    end #def
    
    def self.convert( file, storage_path, options={}, &block )
      worker = responsible( file )&.worker(options.merge(:target => storage_path))
      raise ConverterNotFound unless worker
      worker.preview( File.new(file), &block )
    end #def
    
    ######################################################################################
    #
    # view functions
    #
    ######################################################################################
    def self.formats_for_select(formats=[])
      (FORMATS & Array(formats)).map{|f| [f.to_s,f.to_s]}
    end #def
    
    ######################################################################################
    #
    # class functions: these deal only with settings, not with converter instances
    #
    ######################################################################################
    def self.configured_converters
      begin 
        ::Setting['plugin_redmine_more_previews'].to_h rescue {}
      end["converter"].to_h
    end #def
    
    def self.active_converters
      select_active( configured_converters ).
      select{|key, val| installed?(key)}
    end #def
    
    def self.active_mime_types
      mime_types_of(active_converters).map{|h| select_active(h) }.reduce(&:merge)
    end #def
    
    def self.mime_types_of( converters )
      converters.
        map do |id, converter| 
          converter["mime_types"].to_h.map do |m,opts|
            [m,opts.merge(
              "converter" => id, 
              "mime"      => find(id).mime_types.to_h.dig(m.to_sym, :mime),
              "synonyms"  => find(id).mime_types.to_h.dig(m.to_sym, :synonyms),
              "icon"      => find(id).mime_types.to_h.dig(m.to_sym, :icon)
            )]
          end.to_h
        end.
        compact
    end #def
    
    def self.active_extensions
      extensions_of(active_mime_types)
    end #def
    
    def self.extensions_of( mime_types )
      mime_types.keys
    end #def
    
    def self.mime_doublette?(converter, mime_type)
      mime_types_of(active_converters.except(converter.id.to_s)).
        map{|h| select_active(h).keys }.
        flatten.
        include?(mime_type.to_s)
    end #def
    
    def self.select_active( h )
      h.select{|key,vals| [true, 1, "1"].include?(vals["active"]) }
    end #def
    
    def self.conversion_extension( ext )
      active_mime_types.dig(ext, "format")
    end #def
    
    ######################################################################################
    #
    # instance functions
    #
    ######################################################################################
    def initialize(id)
      @id = id.to_sym
      @mime_types = {}
    end
    
    def to_param
      id
    end
    
    def <=>(converter)
      self.id.to_s <=> converter.id.to_s
    end
    
    def settings(*args)
      if args.empty?
        @settings
      elsif args[0].is_a?(Hash)
        @settings = @settings.to_h.merge(args[0])
      end
    end #def
    
    def public_directory
      File.join(self.class.public_directory, id.to_s)
    end
    
    def public_web_directory
      "/plugin_assets/redmine_more_previews/converters/#{id.to_s}"
    end
    
    # Returns the absolute path to the plugin assets directory
    def assets_directory
      File.join(directory, 'assets')
    end
    
    ######################################################################################
    #
    # field functions
    #
    ######################################################################################
    def mime_types(*args)
      if args.empty?
        @mime_types
      else
        if args.first.is_a?(Hash)
          args.first.each{|mime, opts| opts.assert_valid_keys(:mime, :synonyms, :formats, :icon, :active)}
          @mime_types.merge!(args.first).symbolize_keys!
        elsif %w(String Symbol).include? args.first.class.name
          if args[1].is_a?(Hash)
            args[1].assert_valid_keys(:name, :synonyms, :formats, :active ) 
            @mime_types.merge!(args.first.to_sym => args[1])
          end
        end
        @mime_types.each{|k,v| v[:active] = true unless v.key?(:active)}
      end
    end #def
    
    def worker_attributes
      [:name, :preview_format, :threadsafe, :semaphore, :timeout, :shell_api, :mime_types, :settings].map{|k| [k, try(k)] }.to_h
    end #def
    
    def worker(options={})
      converter_class.new( id, worker_attributes.merge(options) )
    end #def
    
    ######################################################################################
    #
    # special functions
    #
    ######################################################################################
    # Sets a requirement on Redmine version
    # Raises a ConverterRequirementError exception if the requirement is not met
    #
    # Examples
    #   # Requires Redmine 0.7.3 or higher
    #   requires_redmine :version_or_higher => '0.7.3'
    #   requires_redmine '0.7.3'
    #
    #   # Requires Redmine 0.7.x or higher
    #   requires_redmine '0.7'
    #
    #   # Requires a specific Redmine version
    #   requires_redmine :version => '0.7.3'              # 0.7.3 only
    #   requires_redmine :version => '0.7'                # 0.7.x
    #   requires_redmine :version => ['0.7.3', '0.8.0']   # 0.7.3 or 0.8.0
    #
    #   # Requires a Redmine version within a range
    #   requires_redmine :version => '0.7.3'..'0.9.1'     # >= 0.7.3 and <= 0.9.1
    #   requires_redmine :version => '0.7'..'0.9'         # >= 0.7.x and <= 0.9.x
    def requires_redmine(arg)
      arg = { :version_or_higher => arg } unless arg.is_a?(Hash)
      arg.assert_valid_keys(:version, :version_or_higher)
      
      current = Redmine::VERSION.to_a
      arg.each do |k, req|
        case k
        when :version_or_higher
          raise ArgumentError.new(":version_or_higher accepts a version string only") unless req.is_a?(String)
          unless compare_versions(req, current) <= 0
            raise PluginRequirementError.new("#{id} converter requires Redmine #{req} or higher but current is #{current.join('.')}")
          end
        when :version
          req = [req] if req.is_a?(String)
          if req.is_a?(Array)
            unless req.detect {|ver| compare_versions(ver, current) == 0}
              raise ConverterRequirementError.new("#{id} converter requires one the following Redmine versions: #{req.join(', ')} but current is #{current.join('.')}")
            end
          elsif req.is_a?(Range)
            unless compare_versions(req.first, current) <= 0 && compare_versions(req.last, current) >= 0
              raise ConverterRequirementError.new("#{id} converter requires a Redmine version between #{req.first} and #{req.last} but current is #{current.join('.')}")
            end
          else
            raise ArgumentError.new(":version option accepts a version string, an array or a range of versions")
          end
        end
      end
      true
    end
    
    def compare_versions(requirement, current)
      requirement = requirement.split('.').collect(&:to_i)
      requirement <=> current.slice(0, requirement.size)
    end
    private :compare_versions
    
    # Sets a requirement on a Redmine converter version
    # Raises a ConverterRequirementError exception if the requirement is not met
    #
    # Examples
    #   # Requires a converter named :foo version 0.7.3 or higher
    #   requires_redmine_converter :foo, :version_or_higher => '0.7.3'
    #   requires_redmine_converter :foo, '0.7.3'
    #
    #   # Requires a specific version of a Redmine converter
    #   requires_redmine_converter :foo, :version => '0.7.3'              # 0.7.3 only
    #   requires_redmine_converter :foo, :version => ['0.7.3', '0.8.0']   # 0.7.3 or 0.8.0
    def requires_redmine_converter(converter_name, arg)
      arg = { :version_or_higher => arg } unless arg.is_a?(Hash)
      arg.assert_valid_keys(:version, :version_or_higher)
      
      begin
        converter = Converter.find(converter_name)
      rescue ConverterNotFound
        raise ConverterRequirementError.new("#{id} converter requires the #{converter_name} converter")
      end
      current = converter.version.split('.').collect(&:to_i)
      
      arg.each do |k, v|
        v = [] << v unless v.is_a?(Array)
        versions = v.collect {|s| s.split('.').collect(&:to_i)}
        case k
        when :version_or_higher
          raise ArgumentError.new("wrong number of versions (#{versions.size} for 1)") unless versions.size == 1
          unless (current <=> versions.first) >= 0
            raise ConverterRequirementError.new("#{id} converter requires the #{converter_name} converter #{v} or higher but current is #{current.join('.')}")
          end
        when :version
          unless versions.include?(current.slice(0,3))
            raise ConverterRequirementError.new("#{id} converter requires one the following versions of #{converter_name}: #{v.join(', ')} but current is #{current.join('.')}")
          end
        end
      end
      true
    end #def
    
  end #class
end #module
