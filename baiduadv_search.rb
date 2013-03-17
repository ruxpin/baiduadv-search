# encoding: utf-8
require 'digest/md5'
require 'optparse'
require 'sqlite3'
require 'inifile'
require 'rchardet19'
require 'watir'

class Graper
  attr_accessor :keyword_list, :options, :new_pages_temp
  attr_reader :verbose, :browser, :new_pages_insert_sql
  
  def initialize(options={})
    @new_pages_temp, @keyword_list, @new_pages_insert_sql, @grap_links = [], [], [], {}
    @options = options
    fulfill_options
  end

  def fulfill_options
    options.delete('keywords').each do |k|
      keyword_list << k[1]
    end
    options['general'].merge! ({'interval' => '1'}) unless options['general'].has_key?('interval')
    options['general'].merge! ({'rn' => '100'}) unless options['general'].has_key?('rn')
    options['general'].merge! ({'totalpn' => '100'}) unless options['general'].has_key?('totalpn')
    @verbose = options.delete('verbose') ? true :false
    %w[lm site].each do |kn|
      options['general'].merge! ({kn => ''}) unless options['general'].has_key?(kn)
    end
    puts "\n  关键词如下： \n\n  #{keyword_list}\n\n  options如下：\n\n  #{options}" if verbose
  end

  def initialize_browser
    @browser = Watir::Browser.new
    @browser.visible = false unless verbose
  end

  def write_html_meta
    new_pages_temp << '<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />'
  end

  def get_baidu
    initialize_browser
    write_html_meta
    put_separator
    @link_reg = /<H3 class=t>.*?<\/H3>/
    @url_reg = /href=\".*?\"/
    keyword_list.each do |keyword|
      @grap_links[keyword] = {}
      options.each do |profile, settings|
        %w[rn site lm totalpn interval].each do |kn|
          settings[kn] = options['general'][kn] unless settings[kn]
        end
        puts "  <#{profile}> options如下：\n\n  #{settings}\n" if verbose
        puts "  获取关键词【#{keyword}】在 \<#{profile}\> 搜索设置的前#{settings['totalpn']}个搜索结果..\n"
        grap_baidu_links(keyword, profile, settings)
        puts "\n  返回的搜索结果数量: #{@grap_links[keyword][profile].length}\n\n"
      end
      put_separator
    end
    browser.close
    check_new_links
    if new_pages_insert_sql.empty?
      puts "  全部搜索执行完毕，没有新的页面 "
    else
      File.open('new_pages.html', "w") { |f| f.puts new_pages_temp  }
      Watir::Browser.start ("file:///#{Dir.pwd}\\new_pages.html")
      save_new_links_to_db unless new_pages_insert_sql.empty?
    end
  end

  def grap_baidu_links(keyword, profile, settings)
    @base_url = "http://www.baidu.com/s?q1=#{keyword}&q2=&q3=&q4=&rn=#{settings['rn']}&lm=#{settings['lm']}&ct=0&ft=&q5=&q6=#{settings['site']}&tn=baiduadv&pn="
    @grap_links[keyword].merge!({ profile => search_links(0, settings['rn'].to_i, settings['totalpn'].to_i, settings['interval'].to_i, []) })
  end

  def search_links(pn, step, totalpn, interval, links)
    return links if pn >= totalpn
    site = @base_url + pn.to_s
    browser.goto site
    browser.html.each_line do |line|
      links += line.scan(@link_reg) if line.scan(@link_reg)[0]
    end
    pn += step
    sleep interval
    search_links(pn, step, totalpn, interval, links)
  end

#百度搜索每个结果的url都带有唯一的hash值，只需要将获得的hash与title的md5值取出并与数据库已有的hash的md5值比对即可知道是不是没出现过的新结果
#新结果的url_hash和title的md5值将写入数据库中，存为md5是为了减少字段长度，提升sql效率
  def check_new_links
    puts "  在获取的搜索结果中查找新的内容..\n\n"
    begin
      db = SQLite3::Database.open "pagesHub.db"
      @grap_links.each do |keyword, profile_links|
        profile_links.each do |profile, links|
          new_links=[]
          links.each do |line|
            if url = line.scan(@url_reg)[0]
              title_md5 = Digest::MD5.hexdigest(line.gsub(/<.*?>/,"").gsub("\'",'').chomp)
              url_hash_md5 = Digest::MD5.hexdigest(url.gsub("href=","").gsub("\"","").chomp.sub(/^http:\/\/www.baidu.com\/link\?url=..../,""))
              rs = db.execute "select * from pages where url_hash_md5=\'#{url_hash_md5}\' and title_md5=\'#{title_md5}\'"
              if rs.empty?
                new_pages_insert_sql << "insert into pages(title_md5,url_hash_md5) values(\'#{title_md5}\',\'#{url_hash_md5}\')"
                new_links << line.gsub("H3","H5")
              end
            end
          end
          if !new_links.empty?
            new_pages_temp << ('<p>【'+keyword+"】在 "+profile+" 搜索设置的新搜索结果如下（共#{new_links.length}）条："+'</p>')
            new_pages_temp << new_links
            new_pages_temp << '<p>----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----</p>'
            puts "  【"+keyword+"】在 <"+profile+"> 的搜索设置有相关的新链接"+new_links.length.to_s+"条  \n\n"
          else
            puts "  没有【"+keyword+"】在 <"+profile+"> 搜索设置的新链接 \n\n"
          end
        end
      end
      put_separator      
    rescue SQLite3::Exception => e
      puts e
      exit
    ensure
      db.close if db
    end
  end


  def save_new_links_to_db
    begin
      db = SQLite3::Database.open "pagesHub.db"
      db.execute "begin"
      new_pages_insert_sql.each do |insert_sql|
        puts "\nrun sql: #{insert_sql}" if verbose
        db.execute insert_sql
      end
      db.execute "commit"
      puts "已将此次找到的#{new_pages_insert_sql.length}条结果记入数据库"
    rescue SQLite3::Exception => e
      puts e
      exit
    ensure
      db.close if db
    end
  end
  
  def put_separator
    puts ""
    puts "  ----- ----- ----- ----- ----- ----- ----- ----- ----- -----  "
    puts ""
  end
end

options = {}
begin
  option_parser = OptionParser.new do |opts|
    # 这里是这个命令行工具的帮助信息
    opts.banner = "   百度搜索信息更新工具，Created By Rux\n"

    # Option 为initdb，不带argument，用于将switch默认设置成true或false
    options[:init_db] = false
    # 第一项是Short option（没有可以直接在引号间留空），第二项是Long option，第三项是对Option的描述
    opts.on('-i', '--init_db', "初始化程序数据库\n") do
      options[:init_db] = true
    end

    options[:create_db] = false
    opts.on('-c', '--create_db', "创建程序数据库，如要初始化数据库请用-i参数\n") do
      options[:create_db] = true
    end

    options[:verbose] = false
    opts.on('-v', '--verbose', "在verbose模式下运行\n") do
      options[:verbose] = true
    end
    # Option 为name，带argument，用于将argument作为数值解析，留待备用
    # opts.on('-n NAME', '--name Name', 'Pass-in single name') do |value|
    #   options[:name] = value
    # end

    # Option 作为flag，带一组用逗号分割的arguments，用于将arguments作为数组解析，留待备用
    # opts.on('-a A,B', '--array A,B', Array, 'List of arguments') do |value|
    #   options[:array] = value
    # end
  end.parse!
rescue OptionParser::InvalidOption => e
  puts e
  exit 1
end

if options[:create_db]
  begin
    db=SQLite3::Database.new "pagesHub.db"
    db.execute "create table if not exists pages(id INTEGER PRIMARY KEY autoincrement, title_md5 text, url_hash_md5 text)"
    puts "\n数据库创建完毕\n如已有数据库及数据，将不执行任何操作"
    rescue SQLite3::Exception => e
      puts "Exception occured"
      puts e
    ensure
      db.close if db
      exit unless options[:init_db]
  end
end

if options[:init_db]
  begin
    db=SQLite3::Database.open "pagesHub.db"
    db.execute "delete from pages;"
    puts "\n数据库初始化完毕"
    rescue SQLite3::Exception => e
      puts "Exception occured"
      puts e
    ensure
      db.close if db
      exit
  end
end

inifile_encoding = CharDet.detect(File.open("keywords.ini", &:readline)).encoding
ini_file = IniFile.load("keywords.ini", :encoding => inifile_encoding)
main_keys=[]
ini_options={}
ini_file.each do |k|
  main_keys << k.encode("UTF-8", inifile_encoding)
end
main_keys.uniq!
main_keys.each do |ik|
  ini_options[ik]={}
  ini_file[ik].each do |k,v|
    ini_options[ik].merge! ({k.encode("UTF-8", inifile_encoding) => v.encode("UTF-8", inifile_encoding)}) 
  end
end
ini_options['verbose'] = true if options[:verbose]
geter = Graper.new ini_options
geter.get_baidu