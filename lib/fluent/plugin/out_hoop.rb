module FluentExt; end
module FluentExt::PlainTextFormatterMixin
  # config_param :output_data_type, :string, :default => 'json' # or 'attr:field' or 'attr:field1,field2,field3(...)'

  attr_accessor :output_include_time, :output_include_tag, :output_data_type
  attr_accessor :add_newline, :field_separator
  attr_accessor :remove_prefix, :default_tag
  
  def configure(conf)
    super

    @output_include_time = Fluent::Config.bool_value(conf['output_include_time'])
    @output_include_time = true if @output_include_time.nil?

    @output_include_tag = Fluent::Config.bool_value(conf['output_include_tag'])
    @output_include_tag = true if @output_include_tag.nil?

    @output_data_type = conf['output_data_type']
    @output_data_type = 'json' if @output_data_type.nil?

    @field_separator = case conf['field_separator']
                       when 'SPACE' then ' '
                       when 'COMMA' then ','
                       else "\t"
                       end
    @add_newline = Fluent::Config.bool_value(conf['add_newline'])
    if @add_newline.nil?
      @add_newline = true
    end

    @remove_prefix = conf['remove_prefix']
    if @remove_prefix
      @removed_prefix_string = @remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end
    if @output_include_tag and @remove_prefix and @remove_prefix.length > 0
      @default_tag = conf['default_tag']
      if @default_tag.nil? or @default_tag.length < 1
        raise Fluent::ConfigError, "Missing 'default_tag' with output_include_tag and remove_prefix."
      end
    end

    # default timezone: utc
    if conf['localtime'].nil? and conf['utc'].nil?
      @utc = true
      @localtime = false
    elsif not @localtime and not @utc
      @utc = true
      @localtime = false
    end
    # mix-in default time formatter (or you can overwrite @timef on your own configure)
    @timef = @output_include_time ? Fluent::TimeFormatter.new(@time_format, @localtime) : nil

    @custom_attributes = []
    if @output_data_type == 'json'
      self.instance_eval {
        def stringify_record(record)
          record.to_json
        end
      }
    elsif @output_data_type =~ /^attr:(.*)$/
      @custom_attributes = $1.split(',')
      if @custom_attributes.size > 1
        self.instance_eval {
          def stringify_record(record)
            @custom_attributes.map{|attr| (record[attr] || 'NULL').to_s}.join(@field_separator)
          end
        }
      elsif @custom_attributes.size == 1
        self.instance_eval {
          def stringify_record(record)
            (record[@custom_attributes[0]] || 'NULL').to_s
          end
        }
      else
        raise Fluent::ConfigError, "Invalid attributes specification: '#{@output_data_type}', needs one or more attributes."
      end
    else
      raise Fluent::ConfigError, "Invalid output_data_type: '#{@output_data_type}'. specify 'json' or 'attr:ATTRIBUTE_NAME' or 'attr:ATTR1,ATTR2,...'"
    end

    if @output_include_time and @output_include_tag
      if @add_newline and @remove_prefix
        self.instance_eval {
          def format(tag,time,record)
            if (tag[0, @removed_length] == @removed_prefix_string and tag.length > @removed_length) or
                tag == @remove_prefix
              tag = tag[@removed_length..-1] || @default_tag
            end
            @timef.format(time) + @field_separator + tag + @field_separator + stringify_record(record) + "\n"
          end
        }
      elsif @add_newline
        self.instance_eval {
          def format(tag,time,record)
            @timef.format(time) + @field_separator + tag + @field_separator + stringify_record(record) + "\n"
          end
        }
      elsif @remove_prefix
        self.instance_eval {
          def format(tag,time,record)
            if (tag[0, @removed_length] == @removed_prefix_string and tag.length > @removed_length) or
                tag == @remove_prefix
              tag = tag[@removed_length..-1] || @default_tag
            end
            @timef.format(time) + @field_separator + tag + @field_separator + stringify_record(record)
          end
        }
      else
        self.instance_eval {
          def format(tag,time,record)
            @timef.format(time) + @field_separator + tag + @field_separator + stringify_record(record)
          end
        }
      end
    elsif @output_include_time
      if @add_newline
        self.instance_eval {
          def format(tag,time,record);
            @timef.format(time) + @field_separator + stringify_record(record) + "\n"
          end
        }
      else
        self.instance_eval {
          def format(tag,time,record);
            @timef.format(time) + @field_separator + stringify_record(record)
          end
        }
      end
    elsif @output_include_tag
      if @add_newline and @remove_prefix
        self.instance_eval {
          def format(tag,time,record)
            if (tag[0, @removed_length] == @removed_prefix_string and tag.length > @removed_length) or
                tag == @remove_prefix
              tag = tag[@removed_length..-1] || @default_tag
            end
            tag + @field_separator + stringify_record(record) + "\n"
          end
        }
      elsif @add_newline
        self.instance_eval {
          def format(tag,time,record)
            tag + @field_separator + stringify_record(record) + "\n"
          end
        }
      elsif @remove_prefix
        self.instance_eval {
          def format(tag,time,record)
            if (tag[0, @removed_length] == @removed_prefix_string and tag.length > @removed_length) or
                tag == @remove_prefix
              tag = tag[@removed_length..-1] || @default_tag
            end
            tag + @field_separator + stringify_record(record)
          end
        }
      else
        self.instance_eval {
          def format(tag,time,record)
            tag + @field_separator + stringify_record(record)
          end
        }
      end
    else # without time, tag
      if @add_newline
        self.instance_eval {
          def format(tag,time,record);
            stringify_record(record) + "\n"
          end
        }
      else
        self.instance_eval {
          def format(tag,time,record);
            stringify_record(record)
          end
        }
      end
    end
  end

  def stringify_record(record)
    record.to_json
  end

  def format(tag, time, record)
    if tag == @remove_prefix or (tag[0, @removed_length] == @removed_prefix_string and tag.length > @removed_length)
      tag = tag[@removed_length..-1] || @default_tag
    end
    time_str = if @output_include_time
                 @timef.format(time) + @field_separator
               else
                 ''
               end
    tag_str = if @output_include_tag
                tag + @field_separator
              else
                ''
              end
    time_str + tag_str + stringify_record(record) + "\n"
  end

end

class Fluent::HoopOutput < Fluent::TimeSlicedOutput
  Fluent::Plugin.register_output('hoop', self)

  config_set_default :buffer_type, 'memory'
  config_set_default :time_slice_format, '%Y%m%d' # %Y%m%d%H
  # config_param :tag_format, :string, :default => 'all' # or 'last'(last.part.of.tag => tag) or 'none'

  config_param :hoop_server, :string   # host:port
  config_param :path, :string          # /path/pattern/to/hdfs/file can use %Y %m %d %H %M %S and %T(tag, not-supported-yet)
  config_param :username, :string      # hoop pseudo username
  
  include FluentExt::PlainTextFormatterMixin
  config_set_default :output_include_time, true
  config_set_default :output_include_tag, true
  config_set_default :output_data_type, 'json'
  config_set_default :field_separator, "\t"
  config_set_default :add_newline, true
  config_set_default :remove_prefix, nil

  def initialize
    super
    require 'net/http'
    require 'time'
  end

  def configure(conf)
    if conf['path']
      if conf['path'].index('%S')
        conf['time_slice_format'] = '%Y%m%d%H%M%S'
      elsif conf['path'].index('%M')
        conf['time_slice_format'] = '%Y%m%d%H%M'
      elsif conf['path'].index('%H')
        conf['time_slice_format'] = '%Y%m%d%H'
      end
    end

    super

    unless /\A([a-zA-Z0-9][-a-zA-Z0-9.]*):(\d+)\Z/ =~ @hoop_server
      raise Fluent::ConfigError, "Invalid config value on hoop_server: '#{@hoop_server}', needs SERVER_NAME:PORT"
    end
    @host = $1
    @port = $2.to_i
    unless @path.index('/') == 0
      raise Fluent::ConfigError, "Path on hdfs MUST starts with '/', but '#{@path}'"
    end
    @conn = nil
    @header = {'Content-Type' => 'application/octet-stream'}

    @f_separator = case @field_separator
                   when 'SPACE' then ' '
                   when 'COMMA' then ','
                   else "\t"
                   end
  end

  def start
    super

    # okey, net/http has reconnect feature. see test_out_hoop_reconnect.rb
    @authorized_header = {'Content-Type' => 'application/octet-stream'}
    $log.info "connected hoop server: #{@host} port #{@port}"
  end

  def shutdown
    super
  end

  def record_to_string(record)
    record.to_json
  end

  def format(tag, time, record)
    time_str = @timef.format(time)
    time_str + @f_separator + tag + @f_separator + record_to_string(record) + @line_end
  end

  def path_format(chunk_key)
    Time.strptime(chunk_key, @time_slice_format).strftime(@path)
  end

  def send_data(path, data, retries=0)
    conn = Net::HTTP.start(@host, @port)
    conn.read_timeout = 5
    res = conn.request_put("/webhdfs/v1" + path + "?op=append", data, @authorized_header)
    if res.code == '401'
      $log.error "Failed to append, code: #{res.code}, message: #{res.body}"
    end
    if res.code == '404'
      res = conn.request_post("/webhdfs/v1" + path + "?op=create&overwrite=false", data, @authorized_header)
    end
    if res.code == '500'
      if retries >= 3
        raise StandardError, "failed to send_data with retry 3 times InternalServerError"
      end
      sleep 0.3 # yes, this is a magic number
      res = send_data(path, data, retries + 1)
    end
    conn.finish
    if res.code != '200' and res.code != '201'
      $log.warn "failed to write data to path: #{path}, code: #{res.code} #{res.message}"
    end
    res
  end

  def write(chunk)
    hdfs_path = path_format(chunk.key)
    begin
      send_data(hdfs_path, chunk.read)
    rescue
      $log.error "failed to communicate server, #{@host} port #{@port}, path: #{hdfs_path}"
      raise
    end
    hdfs_path
  end
end
