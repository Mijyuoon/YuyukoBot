# frozen_string_literal: true

require 'i18n'
require 'iso8601'

class Duration
  attr_reader :seconds, :minutes, :hours, :days, :weeks

  attr_reader :total_seconds, :total_minutes, :total_hours, :total_days
  alias_method :total, :total_seconds
  alias_method :to_i, :total_seconds
  
  attr_reader :negative
  alias_method :negative?, :negative

  def initialize(value = 0)
    if value.is_a?(String) && value[0] == 'P'
      iso = ISO8601::Duration.new(value)
      @total_seconds = iso.to_seconds.to_i
    elsif value.respond_to?(:to_i)
      @total_seconds = value.to_i
    else
      raise ArgumentError, 'Invalid duration value'
    end

    recalculate!
  end

  def self.dump(obj)
    obj.iso8601
  end

  def self.load(obj)
    self.new(obj)
  end

  def <=>(other)
    other.is_a?(Duration) ? @total_seconds <=> other.to_i : nil
  end

  def +(other)
    Duration.new(@total_seconds + other.to_i)
  end

  def -(other)
    Duration.new(@total_seconds - other.to_i)
  end

  def zero
    @total_seconds == 0
  end

  alias_method :zero?, :zero

  def iso8601
    output = 'P'.dup

    output << "#{@total_days}D" if @total_days > 0

    if @hours > 0 || @minutes > 0 || @seconds > 0
      output << 'T'

      output << "#{@hours}H" if @hours > 0
      output << "#{@minutes}M" if @minutes > 0
      output << "#{@seconds}S" if @seconds > 0
    end

    output << 'T0S' if output == 'P'

    @negative ? "-#{output}" : output
  end

  def format(fmt)
    options = {
      '%w' => @weeks,
      '%d' => @days,
      '%h' => @hours,
      '%m' => @minutes,
      '%s' => @seconds,

      '%H' => '%02d' % @hours,
      '%M' => '%02d' % @minutes,
      '%S' => '%02d' % @seconds,

      '%td' => @total_days,
      '%th' => @total_hours,
      '%tm' => @total_minutes,
      '%ts' => @total_minutes,

      '%~w' => i18n_units(:week, @weeks),
      '%~d' => i18n_units(:day, @days),
      '%~h' => i18n_units(:hour, @hours),
      '%~m' => i18n_units(:minute, @minutes),
      '%~s' => i18n_units(:second, @seconds),

      '%~td' => i18n_units(:day, @total_days),
      '%~th' => i18n_units(:hour, @total_hours),
      '%~tm' => i18n_units(:minute, @total_minutes),
      '%~ts' => i18n_units(:second, @total_seconds),
    }

    fmt.gsub(/%(~?[wdhms]|[HMS]|~?t[dhms]|%)/) {|match| options[match] || match }
  end

  alias_method :strftime, :format

  private

  def recalculate!
    @negative = (@total_seconds < 0)
    @total_seconds = @total_seconds.abs

    @total_minutes = @total_seconds / 60
    @total_hours = @total_seconds / 3600
    @total_days = @total_seconds / 86400

    @seconds = @total_seconds % 60
    @minutes = @total_minutes % 60
    @hours = @total_hours % 24
    @days = @total_days % 7
    @weeks = @total_days / 7
  end

  def i18n_units(name, count)
    I18n.t(name, scope: :duration, default: name.to_s, count: count)
  end
end