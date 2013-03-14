# encoding: utf-8
require 'optparse'
require 'sqlite3'
require 'inifile'
require 'rchardet19'
require 'watir'

class Graper
  attr_accessor :keyword_list, :options, :browser
  
  def initialize(options={})
    @keyword_list = []
    @options = options
    fulfill_options
    initialize_browser
    write_html_meta
  end

  def fulfill_options
    options.delete('keywords').each do |k|
      keyword_list << k[1]
    end
    options['general'].merge! ({'interval' => '1'}) unless options['general'].has_key?('interval')
    options['general'].merge! ({'rn' => '100'}) unless options['general'].has_key?('rn')
    options['general'].merge! ({'totalpn' => '100'}) unless options['general'].has_key?('totalpn')
    if options['general'].has_key?('debug') &&  options['general']['debug'] == '1'
      options['general'].merge! ({'debug' => true })
    else
      options['general'].merge! ({'debug' => false })
    end
    %w[lm site].each do |a|
      options['general'].merge! ({a => ''}) unless options['general'].has_key?(a)
    end
    puts "\n  关键词如下： \n\n  #{keyword_list}\n\n  options如下：\n\n  #{options}" if options['general']['debug']
  end

  def initialize_browser
    @browser = Watir::Browser.new
    @browser.visible = false unless options['general']['debug']
  end

  def write_html_meta
    File.open("new_pages.html","w") do |f|
      f.puts '<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />'
    end
  end

  def get_baidu
    put_separator
    keyword_list.each do |keyword|
      options.each do |k,v|
        v = fulfill_local_options(v)
        puts "  获取关键词【#{keyword}】在\<#{k}\>设置的前#{v['totalpn']}个搜索结果.."
        grap_baidu_links(keyword, k, v)
        save_new_links_to_db(keyword,k)
      end
    end
    browser.close
  end

  def fulfill_local_options(v)
    v['rn'] = options['general']['rn'] unless v['rn']
    v['site'] = options['general']['site'] unless v['site']
    v['lm'] = options['general']['lm'] unless v['lm']
    v['totalpn'] = options['general']['totalpn'] unless v['totalpn']
    v['interval'] = options['general']['interval'] unless v['interval']
    v
  end

  def grap_baidu_links(keyword,k,v)
    pn = 0
    @grap_links = []
    link_reg = /<H3 class=t>.*?<\/H3>/
    while pn < v['totalpn'].to_i
      site = "http://www.baidu.com/s?q1=#{keyword}&q2=&q3=&q4=&rn=#{v['rn']}&lm=#{v['lm']}&ct=0&ft=&q5=&q6=#{v['site']}&pn=#{pn}&tn=baiduadv"
      browser.goto site
      browser.html.each_line do |line|
        if line.scan(link_reg)[0]
          @grap_links << line.scan(link_reg)
        end
      end
      pn += v['rn'].to_i
      sleep v['interval'].to_i
    end
  end

#百度搜索每个结果的url都带有唯一的hash值，只需要将获得的hash值取出并与数据库已有的hash值比对即可知道是不是没出现过的新结果
#新结果的url_hash和title将写入数据库中
  def save_new_links_to_db(keyword,profile)
    puts "  在获取的搜索结果中查找新的内容.."
    url_reg = /href=\".*?\"/
    begin
      db = SQLite3::Database.open "pagesHub.db"
      new_links=[]
      @grap_links.each do |set|
        set.each do |line|
          if url = (line.scan url_reg)[0]
            url.gsub!("href=","").gsub!("\"","").chomp!
            title = line.gsub(/<.*?>/,"").gsub("\'",'').chomp
          end
          url_hash = url.sub(/^http:\/\/www.baidu.com\/link\?url=..../,"")
          stm = db.prepare "select * from pages where url_hash=\'#{url_hash}\' and title=\'#{title}\'"
          found = false
          rs = stm.execute
          found = true if rs.next
          stm.close
          unless found
            puts "\nrun sql: insert into pages(url,title,url_hash) values(\'#{url}\',\'#{title}\',\'#{url_hash}\')" if options['general']['debug']
            db.execute "insert into pages(url,title,url_hash) values(\'#{url}\',\'#{title}\',\'#{url_hash}\')"
            new_links << line.gsub("H3","H5")
          end
        end
      end
      if !new_links.empty?
        File.open("new_pages.html","a") do |f|
          f.puts '<p>【'+keyword+"】在 "+profile+" 设置的新搜索结果如下："+'</p>'
          f.puts new_links
          f.puts '<p>----- ----- ----- ----- ----- -----</p>'
        end
        puts "  有相关的新链接"+new_links.length.to_s+"条  "
      else
        puts "  没有新的链接 No news is good news "
      end
      db.close if db
      put_separator
    rescue
      puts "\n  数据库操作异常，请加参数 -c -i 重置数据库或联系开发人员"
      browser.close
      exit
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
    opts.banner = "   搜索信息更新工具，Created By Rux\n"

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
    db.execute "create table if not exists pages(id INTEGER PRIMARY KEY autoincrement, url text, title text, url_hash text)"
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

geter = Graper.new ini_options
geter.get_baidu