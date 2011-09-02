#!/usr/bin/env ruby
# coding: UTF-8

=begin

= AdHocビルドのipaファイルからiOSデバイスに直接インストールするための plist と HTML を生成する

Authors::   GNUE(鵺)
Version::   1.1 2011-06-02 gnue
Copyright:: Copyright (C) gnue, 2011. All rights reserved.
License::   MIT ライセンスに準拠

　AdHocビルドのipaファイルからiOSデバイスに直接インストールするための plist と HTML を生成する

== 使い方

$ ipa2adhoc.rb baseURL file…

== 注意

* ipaファイルのファイル名に空白が入っているとインストールできません

== 動作環境

* 以下のライブラリが必要です（gem でインストールできます）
  * zipruby
  * CFPropertyList
* PNG を変換する pngcrush は iOS SDK に含まれています

== TODO

== 開発履歴

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
require 'tempfile'
require 'uri'


class IPA
	TOOLS = '/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin'

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
		name = File.basename(saveName, '.*')
		path = "#{name}.png"

		iconFile = 'Icon.png' unless iconFile

		Zip::Archive.open(@path) do |archives|
			archives.each do |a|
				if /^Payload\/.+.app\/#{iconFile}$/ =~ a.name
					icon = a.read

					pngcrush = "#{TOOLS}/pngcrush"
					if File.exists?(pngcrush)
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


def adHocHTML(baseURL, adhocs)
	# adHock用HTMLの生成
	html = DATA.read

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
	if ARGV.length < 2
		cmd = File.basename(__FILE__)
		abort "Usage: #{cmd} baseURL file…\n"
	end

	baseURL = ARGV.shift
	adhocs = []

	# baseURL の末尾を必ず / にしておく
	baseURL = baseURL.gsub(/\/$/, '') + '/'

	# adHock用のファイル生成
	ARGV.each do |f|
		ipa = IPA.new(f, baseURL)
		adhocs << ipa.ganerate
	end

	# Webページの生成
	File.open("index.html", 'w') { |f|
		f.print adHocHTML(baseURL, adhocs)
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
