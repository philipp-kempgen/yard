require 'erb'

module YARD
  module Templates
    module Template
      attr_accessor :class, :options, :sections, :section
      
      include Helpers::BaseHelper
      include Helpers::MethodHelper
    
      def self.included(klass)
        klass.extend(ClassMethods)
      end

      module ClassMethods
        attr_accessor :path, :full_path
        
        def full_paths
          included_modules.inject([full_path]) do |paths, mod|
            paths |= mod.full_paths if mod.respond_to?(:full_paths)
            paths
          end
        end
    
        def initialize(path, full_path)
          self.path = path
          self.full_path = Pathname.new(full_path)
          load_setup_rb
        end
    
        def load_setup_rb
          setup_file = File.join(full_path, 'setup.rb')
          if File.file? setup_file
            module_eval(File.read(setup_file).taint, setup_file, 1)
          end
        end
      
        def new(*args)
          obj = Object.new.extend(self)
          obj.class = self
          obj.send(:initialize, *args)
          obj
        end
      
        def run(*args)
          new(*args).run
        end
      
        def T(*path)
          Engine.template(self, *path)
        end
      
        def is_a?(klass)
          return true if klass == Template
          super(klass)
        end

        def find_file(basename)
          full_paths.each do |path|
            file = path.join(basename)
            return file if file.file?
          end

          nil
        end
      end
    
      def initialize(opts = {})
        @cache, @cache_filename = {}, {}
        self.options = {}
        self.sections = []
        add_options(opts)
        extend(Helpers::HtmlHelper) if options[:format] == :html
        init
      end
    
      def T(*path)
        self.class.T(*path)
      end
    
      def sections(*args)
        @sections.replace(args) if args.size > 0
        @sections
      end
    
      def init
      end
    
      def run(opts = nil, sects = sections, &block)
        return "" if sects.nil?
      
        add_options(opts) if opts
        out = ""
        sects.each_with_index do |s, index|
          next if Array === s
          subsection_index = 0
          @section_index = index
          self.section = s
          out << render_section(section) do |*args|
            text = yieldnext(args.first, subsection_index, &block)
            subsection_index += 1
            text
          end
        end
        out
      end
    
      def render_section(section, &block)
        case section
        when String, Symbol
          if respond_to?(section)
            send(section, &block) 
          else
            erb(section, &block)
          end
        when Module, Template
          section.run(options, &block) if section.is_a?(Template)
        end || ""
      end
    
      def subsections
        subsections = sections[@section_index + 1]
        subsections = nil unless Array === subsections
        subsections
      end
    
      def yieldnext(opts = nil, index = 0, &block)
        sub = subsections
        raise "No subsections" unless sub
        out = ""
        add_options(opts) do
          t = @section_index
          out = render_section(sub[index], &block)
          @section_index = t
        end
        out
      end
          
      def yieldall(opts = nil, &block)
        sub = subsections
        raise "No subsections" unless sub
        out = ""
        sub.count.times do |i|
          out << yieldnext(opts, i, &block)
        end
        out
      end
    
      def erb(section, &block)
        erb = ERB.new(cache(section), nil, '<>')
        erb.filename = cache_filename(section).to_s
        erb.result(binding, &block)
      end
      
      def file(basename)
        file = self.class.find_file(basename)
        raise ArgumentError, "no file for '#{basename}' in #{self.class.path}" unless file
        file.read
      end
      
      def options=(value)
        @options = value
        set_ivars
      end
      
      def inspect
        "Template(#{self.class.path}) [section=#{section}]"
      end
    
      protected
    
      def erb_file_for(section)
        "#{section}.#{options[:format]}.erb"
      end
    
      private
    
      def cache(section)
        content = @cache[section.to_sym]
        return content if content
      
        file = self.class.find_file(erb_file_for(section))
        @cache_filename[section.to_sym] = file
        raise ArgumentError, "no template for section '#{section}' in #{self.class.path}" unless file
        @cache[section.to_sym] = file.read
      end
      
      def cache_filename(section)
        @cache_filename[section.to_sym]
      end
      
      def set_ivars
        options.each do |k, v|
          instance_variable_set("@#{k}", v)
        end
      end
    
      def add_options(opts = {}, &block)
        if opts.nil?
          yield if block_given?
          return
        end
      
        cur_opts = options if block_given?
        self.options = options.merge(opts)
      
        if block_given?
          yield
          self.options = cur_opts 
        end
      end
    end
  end
end

