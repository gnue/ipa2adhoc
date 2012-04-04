#!/usr/bin/env ruby
# coding: UTF-8

=begin

= AdHocビルドのipaファイルからiOSデバイスに直接インストールするための plist と HTML を生成する

Authors::   GNUE(鵺)
Version::   1.2.2 2011-04-04 gnue
Copyright:: Copyright (C) gnue, 2011-2012. All rights reserved.
License::   MIT ライセンスに準拠

　AdHocビルドのipaファイルからiOSデバイスに直接インストールするための plist と HTML を生成する

== 使い方

HTMLの生成

  $ ipa2adhoc.rb [-o OUTPUT] baseURL FILES…
  $ ipa2adhoc.rb [-o OUTPUT] -f CONFIG [FILES…]

config.json と template.html の生成

  $ ipa2adhoc.rb -g

== 設定ファイル

  {
     "baseURL":  "http://foo.com/bar/",			// ベースURL（省略時は第１引数で指定）
     "template": "template.html",				// テンプレートファイル（省略可）
     "files":    ["foo.ipa", "bar.ipa"]			// ipaファイルのリスト（省略可）
  }

== 注意

* ipaファイルのファイル名に空白が入っているとインストールできません

== 動作環境

* 以下のライブラリが必要です（gem でインストールできます）
  * zipruby
  * CFPropertyList
  * json
* PNG を変換する pngcrush は iOS SDK に含まれています

== TODO

* CGI対応

== 開発履歴

* 1.2.2 2012-04-04
  * xcode-select で pngcrush の実行ファイルを探すようにした
* 1.2.1 2011-09-02
  * 出力ディレクトリを指定できるようにした
* 1.2 2011-09-02
  * 設定ファイル（JSON）を指定できるようにした
  * テンプレートを指定できるようにした（設定ファイルで指定）
* 1.1.1 2011-09-02
  * アイコンがみつからなくてもエラーにならないようにした
  * Info.plist に CFBundleIconFile がない場合は CFBundleIconFiles の最初の要素を使うようにした
* 1.1 2011-06-02
  * バイナリplist の読み書きに CFPropertyList を使用するようにした 
  * RubyCocoa を使わないので Mac OS X 以外の環境でも使用できるようになりました
  * Ruby 1.9 に対応
  * pngcrush がない場合は iOS用の PNG をそのまま使用するようにした
* 1.0.1 2011-03-10
  * Mac/PCでもアイコンが見れるように最適化前の PNG を保存するようにした
  * 引数が足りないときに Usage を表示するようにした
* 1.0 2011-02-02
  * とりあえず作ってみた

=end


require 'rubygems'
require 'zipruby'
require 'cfpropertylist'
require 'optparse'
require 'tempfile'
require 'uri'
require 'pathname'


class IPA
	XCODE_SELECT = '/usr/bin/xcode-select'

	if (File.executable?(XCODE_SELECT))
		TOOLS = `#{XCODE_SELECT} -print-path`.chomp+'/Platforms/iPhoneOS.platform/Developer/usr/bin'
	else
		TOOLS = '/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin'
	end

	def initialize(path, baseURL)
		@path = path
		@baseURL = baseURL
		@appInfo = appInfo(path)
	end

	def appInfo(path)
		Zip::Archive.open(path) do |archives|
			archives.each do |a|
				if /^Payload\/.+.app\/Info\.plist$/ =~ a.name
					plist = CFPropertyList::List.new({:data => a.read})
					return CFPropertyList.native_types(plist.value)
				end
			end
		end
	end

	def adhocPlist(appInfo = @appInfo)
		# adHock用plistの生成
		asset = {
			'kind'	 			=> 'software-package',
			'url'	 			=> @baseURL + URI.escape(File.basename(@path)),
		}
		metadata = {
			'bundle-identifier' => appInfo['CFBundleIdentifier'],
			'bundle-version'	=> appInfo['CFBundleVersion'],
			'kind' 				=> 'software',
			'title' 			=> appInfo['CFBundleDisplayName'],
		}
		return {'items' => [{'assets' => [asset], 'metadata' => metadata}]}
	end

	def writeAdhocPlist(saveName = @path)
		# adHock用plistの保存
		name = File.basename(saveName, '.*')
		path = "#{name}.plist"

		plist = CFPropertyList::List.new
		plist.value = CFPropertyList.guess(adhocPlist)
		plist.save(path, CFPropertyList::List::FORMAT_BINARY)

		path
	end

	def writeIconFile(saveName = @path, appInfo = @appInfo)
		# adHock用plistの保存
		iconFile = appInfo['CFBundleIconFile']
		iconFile = appInfo['CFBundleIconFiles'].first if ! iconFile
		name = File.basename(saveName, '.*')
		path = "#{name}.png"

		iconFile = 'Icon.png' unless iconFile

		Zip::Archive.open(@path) do |archives|
			archives.each do |a|
				if /^Payload\/.+.app\/#{iconFile}$/ =~ a.name
					icon = a.read

					pngcrush = "#{TOOLS}/pngcrush"
					if File.executable?(pngcrush)
						# 最適化前の PNG に戻す
						temp = Tempfile.new(path)
						temp.write(icon)
						temp.close

						system(pngcrush, '-revert-iphone-optimizations', '-q', temp.path, path)
					else
						File.new(path, 'w').write(icon)
					end

					return path
				end
			end
		end

		nil
	end

	def ganerate
		adhoc = {}

		adhoc['appName'] = @appInfo['CFBundleDisplayName']
		adhoc['plistFile'] = writeAdhocPlist
		adhoc['iconFile'] = writeIconFile

		adhoc
	end
end


def adHocHTML(baseURL, adhocs, templateFile = nil)
	# adHock用HTMLの生成
	html = File.read(templateFile) if templateFile
	html = DATA.read.lstrip if ! html

	html.gsub(/(<!-- adhoc begin -->)((.|\n)+)(<!-- adhoc end -->)/) {
		st = $1
		templ = $2
		ed = $4

		s = adhocs.map { |adhoc|
			e = templ.clone
			e.gsub!(/__ADHOCK_URL__/, baseURL + URI.escape(File.basename(adhoc['plistFile'])))
			e.gsub!(/__APPICON__/, baseURL + URI.escape(File.basename(adhoc['iconFile']))) if adhoc['iconFile']
			e.gsub!(/__APPNAME__/, adhoc['appName'])
		}

		st + s.join("\n") + ed
	}
end


if __FILE__ == $0
	CMD = File.basename $0

	# 使い方
	def usage
		abort "Usage: #{CMD} [-o OUTPUT] baseURL FILES…\n" +
			  "       #{CMD} [-o OUTPUT] -f CONFIG [FILES…]\n" +
			  "  -o OUTPUT   oputput directory\n" +
			  "  -f CONFIG   use json config file\n" +
			  "  -g          genarete config and template file\n" +
			  "  --help\n"
	end

	# baseURL の末尾を必ず / にしておく
	def directoryURL(url)
		url.gsub(/\/$/, '') + '/'
	end

	def validFile(path, type)
		abort "ERR: #{type} file '#{path}' not exits" if path && ! File.exists?(path)
	end

	def read_json(path)
		validFile(path, 'config')

		begin
			require 'json'

			data = File.read(path)
			JSON.parse(data)
		rescue
			usage
		end
	end

	def ganarate_templates(configFile = 'config.json', templateFile = 'template.html')
		open(templateFile, 'w') { |f|
			f.write(DATA.read.lstrip)
		}

		open(configFile, 'w') { |f|
			f.write <<-EOS
{
	"baseURL":	"",
	"template":	"#{templateFile}",
	"files":	[]
}
			EOS
		}
		exit
	end

	# コマンド引数の解析
	config = {}

	opts = OptionParser.new
	opts.on('-f CONFIG') { |v| config = read_json(v) }
	opts.on('-o OUTPUT') { |v| config['output'] = v }
	opts.on('-g') { ganarate_templates }
	opts.on('--help') { |v| usage }
	opts.parse!(ARGV)

	validFile(config['template'], 'template')
	templateFile = Pathname.new(config['template']).realpath

	# baseURL
	config['baseURL'] = ARGV.shift if ! config['baseURL']
	usage if ! config['baseURL']

	# files
	config['files'] = [] if ! config['files']
	config['files'].concat(ARGV)

	# output
	if config['output'] then
		require 'fileutils'

		begin
			Dir::mkdir(config['output'])
		rescue Errno::EEXIST
		end

		config['files'].each do |f|
			FileUtils.cp(f, config['output'])
		end

		Dir::chdir(config['output'])
	end

	# 初期化
	adhocs = []

	# baseURL の末尾を必ず / にしておく
	baseURL = directoryURL(config['baseURL'])

	# adHock用のファイル生成
	config['files'].each do |f|
		ipa = IPA.new(f, baseURL)
		adhocs << ipa.ganerate
	end

	# Webページの生成
	File.open("index.html", 'w') { |f|
		f.print adHocHTML(baseURL, adhocs, templateFile.to_s)
	}
end


__END__

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">

<head profile="http://gmpg.org/xfn/11">
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<meta name="viewport" id="viewport" content="width=320, user-scalable=no, minimum-scale=1, maximum-scale=1" />
<title>AdHoc</title>

<style>
body {
	font-family: "Helvetica";
	padding: 10px;
}

ul.adhoc {
	list-style-type: none;
}

.adhoc img {
	vertical-align: middle;
	width: 	57px;
	height: 57px;
	margin: 4px;
}
</style>
</head>

<body>

<ul class="adhoc">
<!-- adhoc begin -->
	<li>
	<img src="__APPICON__"/>
	__APPNAME__
	<a href="itms-services://?action=download-manifest&url=__ADHOCK_URL__">Install</a>
	</li>
<!-- adhoc end -->
</ul>

</body>
</html>
