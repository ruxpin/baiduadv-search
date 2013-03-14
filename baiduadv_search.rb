# encoding: utf-8
require 'optparse'
require 'sqlite3'
require 'inifile'
require 'rchardet19'
require 'watir'

class Graper
  attr_accessor :grap_links, :new_links, :keyword_list, :options
  
  def initialize(options={})
    @grap_links = []
    @new_links = []
    @keyword_list = []
    @options = options
    @options.delete('keywords').each do |k|
      @keyword_list << k[1]
    end
    @options['general'].merge! ({'rn' => '100'}) unless @options['general'].has_key?('rn')
    @options['general'].merge! ({'totalpn' => '100'}) unless @options['general'].has_key?('totalpn')
    %w[lm site].each do |a|
      @options['general'].merge! ({a => ''}) unless @options['general'].has_key?(a)
    end
    File.open("new_pages.html","w") do |f|
      f.puts '<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />'
    end
  end
  
  def get_baidu
    puts ""
    put_separator
    keyword_list.each do |keyword|
      grap_links=[]
      options.each do |k,v|
        v['rn'] = options['general']['rn'] unless v['rn']
        v['site'] = options['general']['site'] unless v['site']
        v['lm'] = options['general']['lm'] unless v['lm']
        v['totalpn'] = options['general']['totalpn'] unless v['totalpn']
        puts "  获取关键词【#{keyword}】在\<#{k}\>设置的前#{v['totalpn']}个搜索结果.."
        grap_baidu_links(keyword, k, v)
        save_new_links_to_db(keyword,k)
        sleep 1
      end
    end
  end

  def grap_baidu_links(keyword,k,v)
    pn = 0
    link_reg = /<H3 class=t>.*?<\/H3>/
    while pn < v['totalpn'].to_i
      site="http://www.baidu.com/s?q1=#{keyword}&q2=&q3=&q4=&rn=#{v['rn']}&lm=#{v['lm']}&ct=0&ft=&q5=&q6=#{v['site']}&pn=#{pn}&tn=baiduadv"
      $HIDE_Browser =true
      browser = Watir::Browser.new
      # browser = Watir::IE.new
      browser.goto site
      browser.html.each_line do |line|
        if line.scan(link_reg)[0]
          grap_links << line.scan(link_reg)
        end
      end
      browser.close
      pn += v['rn'].to_i
      sleep 2
    end
  end

  def save_new_links_to_db(keyword,profile)
    puts "  在获取的搜索结果中查找新的内容.."
    url_reg = /href=\".*?\"/
    db = SQLite3::Database.open "pagesHub.db"
    new_links=[]
    grap_links.each do |set|
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
          db.execute "insert into pages(url,title,url_hash) values(\'#{url}\',\'#{title}\',\'#{url_hash}\')"
          new_links << line.gsub("H3","H5")
        end
      end
    end
    if !new_links.empty?
      File.open("new_pages.html","a") do |f|
        f.puts '<p>【'+keyword+"】在 "+profile+" 设置的搜索结果如下："+'</p>'
        f.puts new_links
        f.puts '<p>----- ----- ----- ----- ----- -----</p>'
      end
      puts "  有相关的新链接"+new_links.length.to_s+"条  "
    else
      puts "  没有新的链接 No news is good news "
    end
    db.close if db
    put_separator
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

# puts options.inspect\

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