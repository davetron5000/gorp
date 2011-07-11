class String
  def unindent(n)
    gsub Regexp.new("^#{' '*n}"), ''
  end
  def indent(n)
    gsub /^/, ' '*n
  end
end

unless defined? instance_exec # Rails, Ruby 1.9
  class Proc #:nodoc:
    def bind(object)
      block, time = self, Time.now
      (class << object; self end).class_eval do
        method_name = "__bind_#{time.to_i}_#{time.usec}"
        define_method(method_name, &block)
        method = instance_method(method_name)
        remove_method(method_name)
        method
      end.bind(object)
    end
  end

  module Gorp
    module StringEditingFunctions
      def instance_exec(*arguments, &block)
        block.bind(self)[*arguments]
      end
    end
  end
end

module Gorp
  module StringEditingFunctions
    def highlight
      if self =~ /^\s*<[%!\w].*>/
        start = '<!-- START_HIGHLIGHT -->'
        close = '<!-- END_HIGHLIGHT -->'
      elsif self =~ /;\s*\}?$/
        start = '//#START_HIGHLIGHT'
        close = '//#END_HIGHLIGHT'
      else
        start = '#START_HIGHLIGHT'
        close = '#END_HIGHLIGHT'
      end
      
      if self =~ /\n\z/
        self[/(.*)/m,1] = "#{start}\n#{self}#{close}\n"
      else
        self[/(.*)/m,1] = "#{start}\n#{self}\n#{close}"
      end
    end

    def mark name
      return unless name

      if self =~ /^\s*<[%!\w].*>/
        start = "<!-- START:#{name} -->"
        close = "<!-- END:#{name} -->"
      elsif self =~ /;\s*\}?$/
        start = "//#START:#{name}"
        close = "//#END:#{name}"
      else
        start = "#START:#{name}"
        close = "#END:#{name}"
      end

      if self =~ /\n\z/
        self[/(.*)/m,1] = "#{start}\n#{self}#{close}\n"
      else
        self[/(.*)/m,1] = "#{start}\n#{self}\n#{close}"
      end
    end

    def edit(from, *options, &block)
      if from.instance_of? String
        from = Regexp.new('.*' + Regexp.escape(from) + '.*')
      end

      raise IndexError.new('regexp not matched') unless match(from)

      sub!(from) do |base|
        base.extend Gorp::StringEditingFunctions
        base.instance_exec(base, &block) if block_given?
        base.highlight if options.include? :highlight
        base.mark(options.last[:mark]) if options.last.respond_to? :keys
        base
      end
    end

    def dcl(name, *options, &block)
      options[-1] = {:mark => name} if options.last == :mark

      re = Regexp.new '^(\s*)(class|def|test)\s+"?' + name +
        '"?.*?\n\1end\n', Regexp::MULTILINE
      raise IndexError.new('regexp not matched') unless match(re)

      self.sub!(re) do |lines|
        lines.extend Gorp::StringEditingFunctions
        lines.instance_exec(lines, &block) if block_given?
        lines.mark(options.last[:mark]) if options.last.respond_to? :[]=
        lines.highlight if options.last == :highlight
        lines
      end
    end

    def dup
      super.extend(Gorp::StringEditingFunctions)
    end

    def clear_highlights
      self.gsub! /^ *(\/\/#)\s*(START|END)_HIGHLIGHT\n/, ''
      self.gsub! /^\s*(#|<!--|\/\*)\s*(START|END)_HIGHLIGHT\s*(-->|\*\/)?\n/, ''
    end

    def clear_all_marks
      self.gsub! /^ *(\/\/#)\s*(START|END)(_HIGHLIGHT|:\w+)\n/, ''
      self.gsub! /^\s*(#|<!--|\/\*|\/\/#)\s*(START|END)(_HIGHLIGHT|:\w+)\s*(-->|\*\/)?\n/, ''
    end

    def msub pattern, replacement, option=nil
      if option == :highlight
        replacement.extend Gorp::StringEditingFunctions
        replacement.highlight if option == :highlight
      elsif option.respond_to? :keys
        replacement.extend Gorp::StringEditingFunctions
        replacement.mark(option[:mark]) 
      end

      if replacement =~ /\\[1-9]/
        replacement.gsub! /\\([1-9])/, '#{$\1}'
        replacement = replacement.inspect.gsub('\#','#')
        match(pattern)
        replacement = eval(replacement)
      end

      self[pattern, 1] = replacement
    end

    def all
      self
    end

    def all=(replacement)
      self[/(.*)/m,1]=replacement
    end
  end
end

def edit filename, tag=nil, &block
  $x.pre "edit #{filename.gsub('/',FILE_SEPARATOR)}", :class=>'stdin'

  stale = File.mtime(filename) rescue Time.now-2
  data = open(filename) {|file| file.read} rescue ''
  before = data.split("\n")

  begin
    data.extend Gorp::StringEditingFunctions
    data.instance_exec(data, &block) if block_given?

    # ensure that the file timestamp changed
    now = Time.now
    usec = now.usec/1000000.0
    sleep 1-usec if now-usec <= stale
    open(filename,'w') {|file| file.write data}
    File.utime(stale+2, stale+2, filename) if File.mtime(filename) <= stale

  rescue Exception => e
    $x.pre :class => 'traceback' do
      STDERR.puts e.inspect
      $x.text! "#{e.inspect}\n"
      e.backtrace.each {|line| $x.text! "  #{line}\n"}
    end
    tag = nil

  ensure
    log :edit, filename.gsub('/',FILE_SEPARATOR)

    include = tag.nil?
    highlight = false
    data.split("\n").each do |line|
      if line =~ /START:(\w+)/
        include = true if $1 == tag
      elsif line =~ /END:(\w+)/
        include = false if $1 == tag
      elsif line =~ /START_HIGHLIGHT/
        highlight = true
      elsif line =~ /END_HIGHLIGHT/
        highlight = false
      elsif include
        if highlight or ! before.include?(line)
          outclass='hilight'
        else
          outclass='stdout'
        end

        if line.empty?
          $x.pre ' ', :class=>outclass
        else
          $x.pre line, :class=>outclass
        end
      end
    end
  end
end

def read name
  open(File.join($DATA, name)) {|file| file.read}
end

