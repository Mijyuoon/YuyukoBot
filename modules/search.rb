# frozen_string_literal: true

require 'net/http'
require 'nokogiri'
require 'htmlentities'

module Search
  extend Yuyuko::CommandContainer

  def self.sanitize(text, html = false)
    if html
      @html_coder ||= HTMLEntities.new
      text = @html_coder.decode(text)
      text = text.gsub(/<[^>]+>/, '')
    end

    text.gsub(/([*_~`])/, %q(\\\1))
  end

  def self.google_search(query, offset: 0)
    params = URI.encode_www_form({hl: 'en', q: query, start: offset})

    connection = Net::HTTP.new('www.google.co.uk', 443)
    connection.use_ssl = true

    header = Yuyuko.cfg('mod.search.http_header')
    request = connection.get("/search?#{params}", header)
    html = Nokogiri::HTML.parse(request.body)

    html.css('#rso div.rc').map do |x|
      link, summ = x.css('h3.r > a').first, x.css('div.s span.st').first
      (link && summ) ? {u: link[:href], h: link.content, s: summ.content} : nil
    end.reject!(&:nil?)
  rescue
    []
  end

  def self.google_images(query)
    params = URI.encode_www_form({hl: 'en', tbm: 'isch', q: query})

    connection = Net::HTTP.new('www.google.co.uk', 443)
    connection.use_ssl = true

    header = Yuyuko.cfg('mod.search.http_header')
    request = connection.get("/search?#{params}", header)
    html = Nokogiri::HTML.parse(request.body)

    html.css('div.rg_meta').map {|x| JSON.parse(x.content)['ou'] }
  rescue
    []
  end

  def self.youtube_search(query)
    params = URI.encode_www_form({hl: 'en', search_query: query})

    connection = Net::HTTP.new('www.youtube.com', 443)
    connection.use_ssl = true

    header = Yuyuko.cfg('mod.search.http_header')
    request = connection.get("/results?#{params}", header)
    html = Nokogiri::HTML.parse(request.body)

    html.css('#img-preload > img').map do |x|
      url = x[:src].match(%r{/vi/([\w-]+)/})
      url ? "https://youtu.be/#{url[1]}" : nil
    end.reject!(&:nil?).uniq
  rescue
    []
  end

  command_group(:Search)

  command([:google, :gsearch],
  arg_mode: :concat, arg_types: [:string],
  usage_info: 'mod.search.help.gsearch.usage',
  description: 'mod.search.help.gsearch.desc') do |evt, query|
    message = evt.channel.send_embed('mod.search.embed.gsearch.wait')

    results = google_search(query)
    if results.empty?
      message.edit_embed('mod.search.embed.gsearch.empty')
      next
    end

    page_length = Yuyuko.cfg('mod.search.search_page_items')
    results_pages = (results.length.to_f / page_length).ceil

    results = results.each_with_index.map do |x, i|
      head = sanitize(x[:h], true)
      summ = sanitize(x[:s], true)
      "**#{i+1}. [#{head}](#{x[:u]})**\n#{summ}"
    end

    cancel_time = Yuyuko.cfg('mod.search.button_cancel_time')

    message.interactive_paginate(results_pages,
    delete: true, cancel: cancel_time, owner: evt.message.author) do |index|
      label = Yuyuko.tr('mod.search.gsearch.result', query: query)
      body = results.slice((index - 1) * page_length, page_length)
      body = "#{label}\n\n#{body.join("\n\n")}"

      message.edit_embed('mod.search.embed.gsearch.result',
        body: body, index: index, total: results_pages)
    end
  end

  command([:google_img, :gimages],
  arg_mode: :concat, arg_types: [:string],
  usage_info: 'mod.search.help.gimages.usage',
  description: 'mod.search.help.gimages.desc') do |evt, query|
    message = evt.channel.send_embed('mod.search.embed.gimages.wait')

    results = google_images(query)
    if results.empty?
      message.edit_embed('mod.search.embed.gimages.empty')
      next
    end

    cancel_time = Yuyuko.cfg('mod.search.button_cancel_time')

    message.interactive_paginate(results.length,
    delete: true, cancel: cancel_time, owner: evt.message.author) do |index|
      message.edit_embed('mod.search.embed.gimages.result',
        query: query, image: results[index-1], index: index, total: results.length)
    end
  end

  command([:youtube, :ytsearch],
  arg_mode: :concat, arg_types: [:string],
  usage_info: 'mod.search.help.ytsearch.usage',
  description: 'mod.search.help.ytsearch.desc') do |evt, query|
    message = evt.channel.send_message(text: Yuyuko.tr('mod.search.ytsearch.wait'))

    results = youtube_search(query)
    if results.empty?
      message.edit(text: Yuyuko.tr('mod.search.ytsearch.empty'))
      next
    end

    cancel_time = Yuyuko.cfg('mod.search.button_cancel_time')

    message.interactive_paginate(results.length,
    delete: true, cancel: cancel_time, owner: evt.message.author) do |index|
      message.edit(text: Yuyuko.tr('mod.search.ytsearch.result',
        url: results[index-1], index: index, total: results.length))
    end
  end
end