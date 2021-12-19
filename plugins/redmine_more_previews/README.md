# redmine_more_previews

Redmine plugin to preview various file types in redmine's preview pane. Works for issue attachments, documents module, files module and repositories. This plugin is designed to work with own plugins. That is plugins for plugins.
To preview files this plugin converts the previewed file content to either
 - pdf
 - png, jpg or gif
 - html or inline html
 - text, or
 - xml
 
The appropriate conversion type(s) is/are up to the plugin developer. The available conversion option can be chosen on the plugin configuration page. 
The plugin was developed with thread safety in mind. With caching enabled, it should stand even higher loads.

Currently, there exist the following plugins:

![Libre](doc/libre/logo.png "Libre")

This plugin requires LibreOffice to be installed on your system. LibreOffice must be reachable with "soffice" to the user, the redmine service is executed by.

Libre uses LibreOffice to do the conversion. Libre converts almost everything LibreOffice can convert:

.csv , .doc , .docm , .docx , .dotm , .dotx , .fodg , .fodp , .fods , .fodt , .odb , .odc , .odf , .odg , .odi , .odm , .odp , .ods , .odt , .otg , .oth , .otp , .ots , .ott , .oxt , .potm , .potx , .ppt , .pptm , .pptx , .rtf , .sda , .sdc , .sdd , .sdp , .sds , .sdw , .sgl , .smf , .stc , .std , .sti , .stw , .sxc , .sxd , .sxg , .sxi , .sxm , .sxw , .vor , .xls , .xlsm , .xlsx , .xltm , .xltx 

to either pdf, html, inline, png, jpg or gif.

Please note, that not all conversions have been thoroughly tested yet. Please send files for a conversion test to me, if you are uncertain if your files get converted an can be viewed in a browser. Further, please note that the conversion accuracy strongly depends on the availability of installed fonts. Please consult the LibreOffice portals to see how to install fonts.

Currently, thoroughly tested are: .csv, .doc, .docx, .ppt, .pptx, .xls, .xlsx, .oddt, .rtf

![Cliff](doc/cliff/logo.png "Cliff")

This plugin requires no additional software to be installed on your system. 

Cliff converts

.mime, .eml 

to html.

You can view the .eml file almost like in a professional email viewer, see mail headers and download attachments. Cliff will sweep the .eml files from scripts, event attributes beginning with "on…", url() in css styles and external images. To do an unsafe preview, you can press a button do so and if you trust the .eml or .mime file

![Mark](doc/mark/logo.png "##mark##")

Mark uses Pandoc to do the conversion. Currently supported is:

.md, .textile, .html

![Peek](doc/peek/logo.png "Peek")

Peek lets you preview pdf-Files in the browser. Peek uses imagemagick to do the conversion. Imagemagick uses Ghostscript as a delegate to handle pdf files. Pdf previews can be the full pdf or a png, jpg or gif of the first page. Please note, that the conversion resolution strongly depends on your ImageMagick's configuration in the delegates file. Please consult ImageMagick's configuration help to edit the delegates file.

![Zippy](doc/zippy/logo.png "Zippy")

Peek lets you preview zip, tgz or tar-Files in the browser. Click on an entry to download one individual file from within the compressed file.

![NilText](doc/nil_text/logo.png "NilText") *DO NOT USE IN PRODUCTION* 

NilText lets you see, which data are available for a file conversion. NilText not suited for production use. You can peruse this plugin to learn about the plugin functionality. Please note, that this plugin may reveal a password of a repository. Like all other plugins, **this plugin is deactivated by default**.


### Install

1. download plugin and copy plugin folder redmine_more_previews go to Redmine's plugins folder

2. go to redmine root folder

`bundle install`

to install necessary gems. Install LibreOfiice (for Libre) and/or Pandoc for (for Mark)

3. restart server f.i.  

`sudo /etc/init.d/apache2 restart`

### Uninstall

1. go to plugins folder, delete plugin folder redmine_attachment_categories

`rm -r redmine_more_previews`

3. restart server f.i.  

`sudo /etc/init.d/apache2 restart`

### Use

* Go to Administration -> Plugins -> Redmine More Previews Configuration 

Choose the following options

 - use embed-tag or iframe-tag
 - cache previews (speeds views, may bloat your rails root's tmp folder a bit)
 - activate sub plugins above
 - for each sub plugin activate the file extension for files you want to preview (if you choose two sub plugins converting the same file type, then a warning will be issued and the last activated sub plugin will do the conversion).

**Have fun!**

### Localisations

* English
* German
* Spanish
* French
* Japanese
* Portugese (Brazil)
* Portugese
* Russian
* Chinese

Native speakers: please help to improve localizations

### Change-Log* 

**2.0.1** fixed last minute issues

**2.0.0** Recoded and published, supports redmine 3+, redmine 4+

**1.0.0** Running on Redmine 3.4.6, never published

# replaces
This plugin replaces 
 - redmine_preview_office, 
 - redmine_preview_docx and 
 - redmine_preview_pdf

# best with
This plugin ideally works together with
 - redmine_preview_inline
 - redmine_all_thumbnails
 
# a note on caching
This plugin caches conversions in the Rail tmp-directory. For large repositories (f.i. firm file servers) each conversion will store a copy of the conversion file in the Rails tmp directory and thus the tmp directory may become as large or even larger as the original repository. There are two ways to handle such a situation: 1. swipe Rails tmp/more_previews directory frequently, 2. change the storage path in the plugin's init.rb file to choose a mass storage, which can handle the amount of data.

If two users choose to reload (do a new conversion) concurrently, then thread safety is honored.
 
