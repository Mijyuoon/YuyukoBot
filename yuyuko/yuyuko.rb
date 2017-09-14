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

def yuyuko_load(*params)
  params.each do |kind|
    case kind
      when :loc
        Yuyuko.locale = I18n.default_locale
        I18n.load_path |= Dir['lang/*.yml']
        I18n.load_path |= Dir['lang/module/*.yml']
        I18n.backend.reload!
      when :cfg
        config = Yuyuko.config = {}
        Dir['cfg/*.yml'].each {|fi| config.deep_merge!(YAML::load_file(fi)) }
        Dir['cfg/module/*.yml'].each {|fi| config.deep_merge!(YAML::load_file(fi)) }
      when :mod
        Dir['modules/*.rb'].each {|fi| Yuyuko::Modules.module_eval(File.read(fi), fi) }
      when :all
        yuyuko_load(:loc, :cfg, :mod)
    end
  end
end

def yuyuko_init(name = 'default')
  return nil unless Yuyuko.cfg("core.bots.#{name}")

  config = {
    type: "core.bots.#{name}.login.type",
    client_id: "core.bots.#{name}.login.client_id",
    token: "core.bots.#{name}.login.token",
    ignore_bots: "core.bots.#{name}.ignore_bots",
    ignore_self: "core.bots.#{name}.ignore_self",
    shard_id: "core.bots.#{name}.shard.id",
    num_shards: "core.bots.#{name}.shard.count",
    command_prefix: "core.bots.#{name}.command_prefix",
  }.map {|k,v| [k, Yuyuko.cfg(v)] }.reject! {|_,v| v.nil? }

  yuyuko = Yuyuko::Bot.new(name: name, **config.to_h)
  Yuyuko::Modules.modules.each {|m| yuyuko.include!(m) }

  yuyuko
end

