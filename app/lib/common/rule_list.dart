List<Map<String, dynamic>> ruleList = [
  {
    'name': '全面屏壁纸',
    'description': '一个专为全面屏手机适配的2K,4K超清手机壁纸网站',
    'type': 'image',
    'sourceUrl': 'https://bizhi.wpcoder.cn',
    'discoveryCode': r'''
      (async () => {
        const { data } = await axios.get('https://bizhi.wpcoder.cn/page/1')
        const $ = cheerio.load(data)
        const list = $('ul.wallpaper li').map((i, el) => {
          return {
            title: $(el).find('a').attr('title'),
            cover: $(el).find('img').attr('src'),
          }
        }).toArray()
        return [{
          title: '最新',
          href: null,
          items: list
        }]
      })
    ''',
    'enabled': true,
  },
  {
    'name': '美图🪜',
    'description': '获取美图写真列表',
    'type': 'image',
    'sourceUrl': 'https://meirentu.cc/',
    'discoveryCode': r'''
      (async () => {
        let url = 'https://meirentu.cc/'
        try {
          let { data } = await axios.get(url, {
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
            }
          })
          let $ = cheerio.load(data)
          let list = $('.cl .i_list').map((i, el) => {
            return {
              title: $(el).find('.meta-title').text().trim(),
              cover: $(el).find('img').attr('data-src'),
              href: 'https://meirentu.cc' + $(el).find('a').attr('href'),
              date: $(el).find('.meta-post span').first().text().trim(),
              desc: $(el).find('.cx_like').text().trim()
            }
          }).toArray()
          return [{
            title: '最新',
            href: null,
            items: list
          }]
        } catch (error) {
        }
      })
    ''',
    'enabled': true,
  },
  {
    'name': '小黄书🪜',
    'sourceUrl': 'https://xchina.co',
    'description': '获取小黄书视频列表',
    'type': 'video',
    'discoveryCode': r'''
      (async () => {
        let url = 'https://xchina.co'
        try {
          let { data } = await axios.get(url, {
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
            }
          })
          let $ = cheerio.load(data)
          let list = $('.content-box:has(.header):has(.body):not(.featured-comments)').map((i, el) => {
            let title = $(el).find('.left').text().trim()
            let href = url + $(el).find('.right a').attr('href')

            let items = $(el).find('.right .body').map((i, el) => {
              return {
                title: $(el).find('.item .title a').text().trim(),
                cover: $(el).find('div.img[role="img"]').attr('style')?.match(/url\(['"]?(.*?)['"]?\)/)?.[1],
                subtitle: $(el).find('.model-container').text().trim(),
                href: url + $(el).find('a').attr('href'),
                tags: $(el).find('.tags').text().trim(),
                date: null,
                desc: null
              }
            }).toArray()

            return {
              title,
              href,
              items
            }
          }).toArray()
          return list
        } catch (error) {
        }
      })
    ''',
    'enabled': false,
  },
  {
    'name': '木瓜视频🪜',
    'description': '获取木瓜视频列表',
    'sourceUrl': 'https://91quanji.com',
    'type': 'video',
    'discoveryCode': r'''
      (async () => {
        let url = 'https://91quanji.com'
        try {
          let { data } = await axios.get(url, {
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
            }
          })
          let $ = cheerio.load(data)
          let list = $('#list_videos_videos_index .container').map((i, el) => {
            let title = $(el).find('.title').text().trim()
            let href = url + $(el).find('.buttons a[href^="tag.jsp*"]').attr('href')

            let items = $(el).find('.thumb--videos').map((i, el) => {
              return {
                title: $(el).find('.thumb-spot__title').text().trim(),
                cover: $(el).find('.thumb__img img').attr('src'),
                subtitle: null,
                href: $(el).find('a').attr('href'),
                tags: null,
                date: null,
                desc: null
              }
            }).toArray()

            return {
              title,
              href,
              items
            }
          }).toArray()
          return list
        } catch (error) {
        }
      })
    ''',
    'detailCode': r'''
      (async ({ href }) => {
        let url = 'https://91quanji.com/' + href
        try {
          let { data } = await axios.get(url, {
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
            }
          })
          let $ = cheerio.load(data)

          function I(r) {
            var n = "";
            for (i = 0; i < r.length; ++i)
              n += String.fromCharCode(128 ^ r.charCodeAt(i));
            return n
          }

          // 提取eval(xxx)中间的字符串
          function extractEvalString(str) {
            // 匹配 eval( 和 ) 之间的内容，使用非贪婪匹配
            const match = str.match(/eval\(([\s\S]*?)\)/);
            return match ? match[1] : null;
          }

          let evalStr = extractEvalString($('script[type="text/javascript"]').html())
          evalStr = evalStr.substring(3, evalStr.length - 3)
          let scriptStr = I(evalStr)
          let videoUrl = scriptStr.match(/url:\s*['"]([^'"]+)['"]/)?.[1];

          let list = $('.thumb--videos').map((i, el) => {
            return {
              title: $(el).find('.thumb-spot__title').text().trim(),
              cover: $(el).find('.thumb__img img').attr('src'),
              subtitle: null,
              href: null,
              tags: null,
              date: null,
              desc: null
            }
          }).toArray()
          return { videoUrl, list }
        } catch (error) {
          console.error(error);
        }
      })
    ''',
    'enabled': false,
  },
  {
    'name': '蜜桃视频',
    'sourceUrl': 'https://www.mmtt06.com',
    'description': '蜜桃视频',
    'type': 'video',
    'discoveryCode': r'''
      (async () => {
        const map = {
          '吃瓜': 'https://www.mmtt06.com/categoryPaginate/10030-0-0-0.html',
          'AV': 'https://www.mmtt06.com/categoryPaginate/10011-0-0-0.html',
          'ONLYFANS': 'https://www.mmtt06.com/categoryPaginate/10032-0-0-0.html',
        }
        let playBaseUrl = 'https://107.174.106.254:15511'
        const result = []
        for (const [key, value] of Object.entries(map)) {
          let items = []
          try {
            let { data } = await axios.get(value, {
              headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
              }
            })
            items = [...(data?.data || []).map(item => {
              let playPath = item?.playPreviewPath?.replace('/preview', '/index')
              return {
                title: item.title,
                cover: `${playBaseUrl}${item.imagePath}`,
                subtitle: null,
                href: `${playBaseUrl}${playPath}`,
                tags: item?.tags?.map((tag) => tag.name).join(', '),
                date: null,
                desc: null,
              }
            })]
            
          } catch (error) {
            console.error(error);
            
          }
          result.push({
            title: key,
            href: value,
            items
          })
        }
        return result
      })
    ''',
    'searchCode': r'''
      (async ({ keyword }) => {
        let baseUrl = `https://www.mmtt06.com/searchPaginate/${keyword}/1.html`
        let playBaseUrl = 'https://107.174.106.254:15511'

        let { data } = await axios.get(baseUrl, {
          headers: {
            'User-Agent': ua,
          }
        })
        return (data?.data || []).map(item => {
          let playPath = item?.playPreviewPath?.replace('/preview', '/index')
          return {
            baseUrl: 'https://www.mmtt06.com',
            title: item.title,
            cover: `${playBaseUrl}${item.imagePath}`,
            subtitle: null,
            href: `${playBaseUrl}${playPath}`,
            tags: item?.tags?.map((tag) => tag.name).join(', '),
            date: null,
            desc: null,
          }
        })
      })
    ''',
    'detailCode': r'''
      (async ({ href }) => {
        let baseUrl = 'https://107.174.106.254:15511'
        return { videoUrl: href, list: [] }
      })
    ''',
    'enabled': false,
  },
  {
    'name': 'JAVMENU',
    'sourceUrl': 'https://javmenu.com/',
    'description': 'JAV目錄大全 | 世界上最齊全的日本AV資料庫',
    'type': 'video',
    'discoveryCode': r'''
      (async () => {
        const { data } = await axios.get('https://javmenu.com/zh/');
        
        // 使用 cheerio 解析 HTML
        const $ = cheerio.load(data);
        const result = [];
        
        // 遍历所有 .video-list-item 元素
        $('.video-list-item').each((index, element) => {
          const item = {
            url: $(element).find('a').attr('href'),
            cover: $(element).find('.card-img-top').attr('data-src'),
            title: $(element).find('.card-text').text().trim(),
            desc: $(element).find('.text-muted').text().trim()
          };
          result.push(item);
        });
        result.shift()
        
        return {
          title: '热门',
          href: 'https://javmenu.com/',
          items: result
        };
      })
    ''',
    'searchCode': r'''
      (async ({ keyword }) => {
        const { data } = await axios.get('https://javmenu.com/zh/search?wd=' + keyword);
      
        // 使用 cheerio 解析 HTML
        const $ = cheerio.load(data);
        const result = [];
        
        // 遍历所有 .video-list-item 元素
        $('.video-list-item').each((index, element) => {
          const item = {
            url: $(element).find('a').attr('href'),
            cover: $(element).find('.card-img-top').attr('data-src'),
            title: $(element).find('.card-text').text().trim(),
            desc: $(element).find('.text-muted').text().trim()
          };
          result.push(item);
        });
        result.shift()
        
        return result;
      })
    ''',
    'detailCode': r'''
      (async ({ url, href }) => {
        const { data } = await axios.get('https://javmenu.com/zh/SDMM-087');
        
        // 使用 cheerio 解析 HTML
        const $ = cheerio.load(data);
        let videoUrl = $('#seo-main-video').attr('src')
        let cover = $('#seo-main-video').attr('poster')
        const result = [];
        
        // 遍历所有 .video-list-item 元素
        $('.video-list-item').each((index, element) => {
          const item = {
            url: $(element).find('a').attr('href'),
            cover: $(element).find('.card-img-top').attr('data-src'),
            title: $(element).find('.card-text').text().trim(),
            desc: $(element).find('.text-muted').text().trim()
          };
          result.push(item);
        });
        result.shift()
        
        return {
          videoUrl,
          cover,
          list: result
        };
      })
    ''',
    'version': '1.0.0',
    'enabled': true,
  },
];