#!/usr/bin/env ruby

require 'nokogiri'
require 'open-uri'
require 'uri'
require 'csv'
require 'cgi'

PARTNERS = 'https://access.kfit.com/partners'
CSV_FILE = 'kfit_partners.csv'

def fetch_partners_page
  puts "Fetching #{PARTNERS}..."
  return Nokogiri::HTML(open(PARTNERS))
end

def get_html_partner_names(doc)
  doc.css("li.each-card").css("h3").css("a").map do |e|
    e.text
  end
end

def get_html_partner_ratings(doc)
  doc.css("li.each-card").css("span.rating").map do |e|
    e.text
  end
end

def get_partner_details_inline_js(doc)
  inline_js = doc.xpath("//script")
end

def get_js_extract_partner_details(doc)
  extract = doc.xpath("//script")
  inline_js = extract.select { |script| script.text.include? "kfitMap.outlets.push" }
  inline_js.map { |script| script.text }
  # "kfitMap.outlets.push({\n  id: '1165',\n  company_id: '156',\n  name: 'YogaonethatIwant Studios',\n  address: '20A Persiaran Zaaba, Taman Tun Dr Ismail, 60000 Kuala Lumpur',\n  city: 'kuala-lumpur',\n  position: new google.maps.LatLng('3.141962', '101.628099')\n});", ...]
end

def js_to_details(doc)
  js_extract = get_js_extract_partner_details(doc)

  pat1 = /kfitMap\.outlets\.push\({(.*)}\);/m
  res1 = js_extract.map do |e|
    m = pat1.match(e)[1]
    m.strip
  end
  # ["id: '1165',\n  company_id: '156',\n  name: 'YogaonethatIwant Studios',\n  address: '20A Persiaran Zaaba, Taman Tun Dr Ismail, 60000 Kuala Lumpur',\n  city: 'kuala-lumpur',\n  position: new google.maps.LatLng('3.141962', '101.628099')", ...]

  # Construct an array of partner detail hashes
  details = []
  res1.each do |e|
    maps = e.split("\n")
    h = {}
    # ["id: '1165',", "  company_id: '156',", "  name: 'YogaonethatIwant Studios',", "  address: '20A Persiaran Zaaba, Taman Tun Dr Ismail, 60000 Kuala Lumpur',", "  city: 'kuala-lumpur',", "  position: new google.maps.LatLng('3.141962', '101.628099')", ...]
    maps.each do |m|
      k, v = m.split(':', 2) # name: 'Crazy Monkey Defense : Boxing', -> ["name", " 'Crazy Monkey Defense : Boxing',"]
      k = k.strip.to_sym
      v = v.strip.chomp(',').gsub(/^'|'$/, '')
      h[k] = v

      # :plain_name key stores name converted from eg 'Lekir Fitness &amp; Mix Martial Arts Studio' to 'Lekir Fitness & Mix Martial Arts Studio'
      if k == :name
        plain_name = CGI.unescapeHTML(v) # Technique #1
        # plain_name = Nokogiri::HTML.parse(v).text # Technique #2
        h[:plain_name] = plain_name
      end

      # Convert addresses that look like 'Unit 28 &amp; 30 - 2' to 'Unit 28 & 30 - 2'
      if k == :address
        h[:address] = CGI.unescapeHTML(v)
      end

      # Create additional keys for :latitude & longitude from key :position
      if k == :position
        latlong = /google\.maps\.LatLng\('(.*)', '(.*)'\)/.match(v)
        h[:latitude] = latlong[1]
        h[:longitude] = latlong[2]
      end

    end

    # :partner_page stores partner page detail URI
    h[:partner_page] = "https://access.kfit.com/partners/#{h[:company_id]}?city=#{h[:city]}"

    details << h
  end

  return details
  # [{:id=>"1165", :company_id=>"156", :name=>"YogaonethatIwant Studios", :address=>"20A Persiaran Zaaba, Taman Tun Dr Ismail, 60000 Kuala Lumpur", :city=>"kuala-lumpur", :position=>"new google.maps.LatLng('3.141962', '101.628099')"}, ...]
end

def fetch_parse_page(page)
  puts "Fetching & parsing #{page}"
  return Nokogiri::HTML(open(page))
end

def get_partner_phone(names, js_details)
  phones = []
  names.each_with_index do |name, index|
    matched_js_details_hash = js_details.select { |e| e[:plain_name] == name }[0]
    company_id = matched_js_details_hash[:company_id]
    partner_page = matched_js_details_hash[:partner_page]

    # Step 1
    doc = fetch_parse_page(partner_page)
    first_schedule = doc.css("td.reserve-col a")[0] # => "/schedules/718843"
    if first_schedule
      schedule_page = 'https://access.kfit.com' + doc.css("td.reserve-col a")[0]['href']
    else
      schedule_page = ''
    end

    # Step 2
    if schedule_page != ''
      doc = fetch_parse_page(schedule_page)
      contact_number = doc.css("ul.activity-slot-details p.minor")[1].text
    else
      puts "No reservation found for company_id: #{company_id} -> phone set to ''"
      contact_number = ''
    end

    # Step 3
    phones << {name: name, contact_number: contact_number}
  end

  return phones
end

def write_to_csv(names, ratings, js_details, phones)
  CSV.open(CSV_FILE, "wb") do |csv|
    names.each_with_index do |name, index|
      phone = phones.select { |e| e[:name] == name }[0][:contact_number]
      matched_js_details_hash = js_details.select { |e| e[:plain_name] == name }[0]
      row = [
              *pluck_values_from_hash(
                matched_js_details_hash, [
                  :city, :plain_name, :address, :latitude, :longitude
                ]
              ), 
              ratings[index],
              phone
            ]
      puts "Writing to CSV: #{row}"
      csv << row
    end
  end
end

def pluck_values_from_hash(hash={}, keys=[])
  keys.map { |key| hash[key]}
end

def process_partners
  doc = fetch_partners_page
  names = get_html_partner_names(doc)
  ratings = get_html_partner_ratings(doc)
  js_details = js_to_details(doc)
  phones = get_partner_phone(names, js_details)
  write_to_csv(names, ratings, js_details, phones)
end


if __FILE__ == $0
  process_partners
end
