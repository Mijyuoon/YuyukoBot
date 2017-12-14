I18n.load_path |= Dir['lang/*.yml']
I18n.load_path |= Dir['lang/module/*.yml']
I18n.default_locale = :en

module Yuyuko
  LOCALIZE_REGEX = /^t@([\w\$]+(?:\.[\w\$]+)*)$/
  REPLACE_REGEX  = /^s([tl])?@(\w+[?!]?)(?:\|([\w\$]+(?:\.[\w\$]+)*))?$/

  module Modules
    def self.modules
      constants.map {|x| const_get(x) }.select {|x| x.is_a?(Module) }
    end
  end

  class << self
    attr_accessor :locale
    attr_accessor :config

    def tr(key, values = {})
      values[:locale] = @locale
      I18n.translate!(key, values)
    rescue I18n::MissingTranslationData
      key
    end

    def lc(key, values = {})
      values[:locale] = @locale
      I18n.localize(key, values)
    end

    def cfg(path, copy = false)
      cfg = path ? @config.dig(*path.split('.')) : @config
      copy ? Marshal.load(Marshal.dump(cfg)) : cfg
    end

    def localize!(object, values = {})
      return object if object.frozen?

      case object
        when String
          object = object.dup if object.frozen?
          if (mx = object.match(LOCALIZE_REGEX))
            object[0..-1] = tr(mx[1], values)
          elsif (mx = object.match(REPLACE_REGEX))
            subs = values[mx[2].to_sym]&.to_s
            case mx[1]
              when 't' then subs = tr(subs, values)
              when 'l' then subs = lc(subs, values)
            end if subs
            object[0..-1] = subs || (mx[3] ? tr(mx[3], values) : '')
          end
          object
        when Array
          object.each_with_index do |v, i|
            object[i] = localize!(v, values)
          end
        when Hash
          object.each_pair do |k, v|
            object[k] = localize!(v, values)
          end
        else
          object
      end
    end
  end
end

module YuyukoInit
  CONFIG_ROOT = 'core.bots.*'

  CONFIG_ITEMS = {
    type: 'login.type',
    client_id: 'login.client_id',
    token: 'login.token',
    ignore_bots: 'ignore_bots',
    ignore_self: 'ignore_self',
    shard_id: 'shard.id',
    num_shards: 'shard.num',
    command_prefix: 'command_prefix',
  }.freeze

  @instances = {}

  class << self
    def reload_locale
      Yuyuko.locale = I18n.default_locale
      I18n.load_path |= Dir['lang/*.yml']
      I18n.load_path |= Dir['lang/module/*.yml']
      I18n.backend.reload!
      nil
    end

    def reload_config
      config = Yuyuko.config = {}
      Dir['cfg/*.yml'].each {|fi| config.deep_merge!(YAML::load_file(fi)) }
      Dir['cfg/module/*.yml'].each {|fi| config.deep_merge!(YAML::load_file(fi)) }
      nil
    end

    def reload_modules
      Dir['modules/*.rb'].each {|fi| Yuyuko::Modules.module_eval(File.read(fi), fi) }
      Yuyuko::Modules.modules.each {|m| @instances.each_value {|x| x.include!(m) } }
      nil
    end

    def get_config(name)
      basepath = CONFIG_ROOT.gsub('*', name)
      raise ArgumentError, "Cannot find bot configuration '#{name}'" unless Yuyuko.cfg(basepath)

      CONFIG_ITEMS.map {|k,v| [k, Yuyuko.cfg("#{basepath}.#{v}")] }.delete_if {|_,v| v.nil? }.to_h
    end

    def start_instance(name, async:)
      return if @instances[name]

      config = get_config(name)
      inst = Yuyuko::Bot.new(name: name, **config)
      Yuyuko::Modules.modules.each {|m| inst.include!(m) }

      @instances[name] = inst
      inst.connect(async)
      nil
    end
  end

  reload_locale
  reload_config
  reload_modules
end
