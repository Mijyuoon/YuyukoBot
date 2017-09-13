# frozen_string_literal: true

module Memes
  extend Yuyuko::CommandContainer

  def self.levenshtein(s1, s2)
    prev_it = (s2.length + 1).times.to_a
    curr_it = Array.new(s2.length + 1)

    s1.chars.each_with_index do |c1, i|
      curr_it[0] = i + 1

      s2.chars.each_with_index do |c2, j|
        curr_it[j + 1] = [
          curr_it[j] + 1,
          prev_it[j + 1] + 1,
          prev_it[j] + (c1 != c2 ? 1 : 0)
        ].min
      end

      prev_it = curr_it.dup
    end

    prev_it.last
  end

  def self.butcher_string(input, sample, output, maxdist)
    dist = levenshtein(input.downcase, sample)
    return nil if dist > maxdist

    in_letters = input.scan(/\p{Alpha}/).length
    out_letters = output.scan(/\p{Alpha}/).length

    in_upcase = []
    input.scan(/\p{Upper}/) {|x| in_upcase << $~.offset(0).first }
    out_upcase = in_upcase.map {|x| x * out_letters / in_letters }.uniq

    output = output.dup

    out_upcase.each {|i| output[i] = output[i].upcase }
    dist.times { output[rand(output.length-1)] = '' }

    output
  end

  event(:create_message) do |evt|
    maxdist = Yuyuko.cfg('mod.memes.butcher_distance')
    strings = Yuyuko.cfg('mod.memes.butcher_strings')

    strings&.each do |str|
      sample, output = str['in'], str['out']

      if (message = butcher_string(evt.content, sample, output, maxdist))
        evt.channel.send_message(text: message)
        next
      end
    end
  end
end