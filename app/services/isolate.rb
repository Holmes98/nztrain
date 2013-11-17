require 'open3'

class Isolate
  RESOURCE_OPTIONS = { :time => '-t', :wall_time => '-w', :mem => '-m', :stack => '-k', :processes => '-p', :meta => '-M', :noexec => nil } # TODO: :quota
  CONFIG = YAML.load_file(File.expand_path('config/isolate.yml', Rails.root))

  # Create an isolate box to execute commands within.
  # Pass a block which will be instance_exec-ed, giving access to exec, popen, fopen, ...
  # 
  # Alternatively, the isolate box is passed as an argument to a block with an arity, which is not instance_exec-ed
  def self.box &block
    isolate = self.new
    if block.arity == 0
      isolate.instance_exec &block
    else
      yield isolate
    end if block_given?
    true
  rescue LockError => e
    false
  ensure
    isolate.send :destroy
  end
  
  class LockError < StandardError; end
  class UnlockError < StandardError; end

  # Execute a single command in isolate context
  # 
  # Examples:
  #   Isolate.box { exec("/bin/ls", "/") }
  #   Isolate.box { exec("/bin/ls /") }
  #   Isolate.box do |box|
  #     box.exec "/bin/touch asdf"
  #     box.exec "/bin/ls"
  #   end
  #
  # options
  # :in
  #   specify stdin (filename, symbol, pipe), and optionally flags
  # :out
  #   specify stdout
  # :err
  #   specify stderr
  def exec command
    options = command.extract_options!
    options.assert_valid_keys(:in, :out, :err, *RESOURCE_OPTIONS.keys)
    command = self.class.send(:process_command, command)

    self.class.send(:sandbox_command, @box_id, command, extract_resource(options)) do |command|
      system(*command, options)
    end
  end

  # popen a single command in isolate context
  #
  # Example:
  #   Isolate.box { popen("/bin/ls") {|io| puts io.read} }
  def popen command, mode = "r", options = {}, &block
    options, mode = mode, "r" if mode.is_a? Hash
    options.assert_valid_keys(:err, *RESOURCE_OPTIONS.keys)
    command = self.class.send(:process_command, command)

    self.class.send(:sandbox_command, @box_id, command, extract_resource(options)) do |command|
      IO.popen [*command,options], mode, &block
    end
  end

  def popen2 command, options = {}, &block
    options.assert_valid_keys(*RESOURCE_OPTIONS.keys)
    command = self.class.send(:process_command, command)
    
    self.class.send(:sandbox_command, @box_id, command, extract_resource(options)) do |command|
      Open3.popen2 *command, options, &block
    end
  end

  def popen3 command, options = {}, &block
    options.assert_valid_keys(*RESOURCE_OPTIONS.keys)
    command = self.class.send(:process_command, command)
    
    self.class.send(:sandbox_command, @box_id, command, extract_resource(options)) do |command|
      Open3.popen3 *command, options, &block
    end
  end

  # Example:
  #   Isolate.box { puts `/bin/ls /` }
  def `(command)
    r, w = IO.pipe
    exec(command, {:out => w})
    w.close
    output = r.read
    r.close
    output
  end

  # Identical to File.open, except that the filename is automatically appended to the box path
  #
  # Example:
  #   Isolate.box do
  #     fopen("test","w") { |f| f.write("hello world\n") }
  #     exec("/bin/cat test")
  #   end
  def fopen filename, mode = "r", options = {}, &block
    File.open(expand_path(filename), mode, options, &block)
  end

  def tmpfile basename = 'tmpfile'
    basename = Array(basename) + ['']
    tmpname = 'tmp/' + basename.join
    prng = Random.new
    int = prng.rand(100)
    while File.exist?(fullname = expand_path(tmpname))
      int += prng.rand(11..100)
      tmpname = 'tmp/' + basename[0] + int.to_s + basename[1]
    end
    FileUtils.mkdir_p(File.dirname(fullname))
    FileUtils.touch(fullname)

    if block_given?
      begin
        yield tmpname
      ensure
        FileUtils.remove(fullname)
      end
    else
      return tmpname
    end
  end

  def exist? filename
    File.exist?(expand_path(filename))
  end

  # cleans the box directory of any files by re-initializing
  def clean!
    system "isolate -b#{@box_id} --init", :out => '/dev/null'
  end

  def expand_path filename
    self.class.send(:file_expand, @box_id, filename)
  end

  protected

  def initialize
    response = Kernel.send :`, "isolock --lock"
    if $?.success?
      @box_id = response.to_i
    else
      raise LockError
    end
  end

  def destroy
    return if @box_id.nil?
    system "isolock --free #{@box_id}"
    raise UnlockError unless $?.success?
  end

  def extract_resource(options)
    options.extract!(*RESOURCE_OPTIONS.keys).select{|k,v|v}
  end

  class << self
    def parse_meta raw
      Hash[raw.split.map{|e|e.split':'}]
    end

    private
    def sandbox_command box_id, command, options = {}
      boxcmd = ["isolate","-b#{box_id}"] + directory_bindings(options.extract!(:noexec)) + sandbox_options(options) + environment + ["--run","--"]
      yield boxcmd + command
    end

    def sandbox_options options = {}
      # TODO: add --cg, --cg-timing --cg-mem
      options[:processes] = 1 if options[:processes] == false
      options[:processes] = nil if options[:processes] == true
      options.map{ |k,v| "#{RESOURCE_OPTIONS[k]}#{v}" }
    end

    def file_expand box_id, filename
      File.expand_path(filename,"/tmp/box/#{box_id}/box")
    end

    def directory_bindings options = {}
      options.reverse_merge!({:noexec => false}).assert_valid_keys(:noexec)
      {'bin' => [], 'dev' => ['dev'], 'lib' => [], 'lib64' => [], 'usr' => []}.map do |dir,opt|
        fullpath = File.expand_path(dir, isolate_root)
        boxpath = File.expand_path(dir, "/")
        opt << 'noexec' if options[:noexec]
        binding = opt.unshift(fullpath).join(':')
        next "--dir=#{boxpath}=" unless File.exist?(fullpath)
        "--dir=#{boxpath}=#{binding}"
      end.compact
    end

    # returns root if debootstrap enabled
    def isolate_root
      CONFIG['root']
    end

    def environment
      Shellwords.split(`cat #{isolate_root}/etc/environment`).map do |pair|
        "--env=#{pair}"
      end
    end

    def process_command command
      if command.is_a? String
        command = Shellwords.split(command)
      elsif command.is_a? Array
        command
      else
        raise ArgumentError
      end
    end
  end
end