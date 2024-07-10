# 基于neo4j知识图谱的电影知识问答
## 本项目包括三部分：导入数据、知识图谱生成以及问答系统生成
## 一、导入数据
### 导入库
```import requests
from lxml import etree
import csv
```
### 定义数据列名称
```top250_url = 'https://movie.douban.com/top250?start={}&filter='
movie_name = '名称'
movie_year = '年份'
movie_country = '国家'
movie_type = '类型'
movie_director = '导演'
movie_assess = '评价人数'
movie_score = '评分'
movie_num = 0
```
### 用Xpath抓取并生成csv文件
```with open('top250_movie.csv','w',newline = '',encoding = 'utf-8') as f:
    writer = csv.writer(f)
    writer.writerow([movie_num,movie_name,movie_year,movie_country,movie_type,movie_director,movie_assess,movie_score])
    for lists in range(10):
        movie_content = requests.get(top250_url.format(lists*25)).text
        selector = etree.HTML(movie_content)
        all_list = selector.xpath('//*[@id="content"]/div/div[1]/ol/li')
        for item in all_list:
            movie_name = item.xpath('div/div[2]/div[1]/a/span[1]/text()')[0]
            movie_assess = item.xpath('div/div[2]/div[2]/div/span[4]/text()')[0][:-3]
            movie_score = item.xpath('div/div[2]/div[2]/div/span[2]/text()')[0]
            movie_num += 1
            # 下面将电影的介绍信息进行整理
            movie_intro = item.xpath('div/div[2]/div[2]/p[1]/text()')
            movie_actor_infos = movie_intro[0].lstrip().split('\xa0\xa0\xa0')
            movie_other_infos = movie_intro[1].lstrip().rstrip().split('\xa0/\xa0')
            # 下面是导演信息
            movie_director = movie_actor_infos[0][3:]
            # 下面是电影上映的年份
            movie_year = movie_other_infos[0]
            # 下面是电影的国家
            movie_country = movie_other_infos[1]
            # 下面是电影的类型
            movie_type = movie_other_infos[2]
            
            writer.writerow([movie_num,movie_name,movie_year,movie_country,movie_type,movie_director,movie_assess,movie_score])
The project now supports three modes of context search:
```
### 数据展示
![截图20240710101757](https://github.com/ClaireZUO-2000/DOUBAN-MOVIE-QA/assets/172008743/8c80ebbb-6b6e-41d5-88d5-83c10d0860ea)

## 二、知识图谱生成
### 导入neo4j（neo4j社区版）
### 将csv文件放入neo4j文件夹import文件夹，然后在neo4j brower中运行以下cypher脚本
```
// 创建电影节点
LOAD CSV WITH HEADERS FROM 'file:///top250_movie.csv' AS line
CREATE (:Movie {
  movieID: line.movieID,
  name: line.name,
  year: toInteger(line.year),
  comments: line.comments,
  rank: toInteger(line.rank)
});

// 创建国家节点
LOAD CSV WITH HEADERS FROM 'file:///top250_movie.csv' AS line
MERGE (c:Country { name: line.country });

// 创建导演节点
LOAD CSV WITH HEADERS FROM 'file:///top250_movie.csv' AS line
MERGE (d:Director { name: line.director });

// 创建关系
LOAD CSV WITH HEADERS FROM 'file:///top250_movie.csv' AS line
MATCH (m:Movie { movieID: line.movieID })
MATCH (c:Country { name: line.country })
CREATE (m)-[:PRODUCED_IN]->(c);

// 创建其他关系，如导演和电影之间的关系
LOAD CSV WITH HEADERS FROM 'file:///top250_movie.csv' AS line
MATCH (m:Movie { movieID: line.movieID })
MATCH (d:Director { name: line.director })
CREATE (d)-[:DIRECTED]->(m);
```

### 以电影、国家、导演为节点，构建起的知识网络展示如下：
![image](https://github.com/ClaireZUO-2000/DOUBAN-MOVIE-QA/assets/172008743/666276c8-d7fc-4cc7-add3-c858ba52cb1c)

## 三、问答系统生成
### 有了neo4j知识图谱，就可以借助图谱完成一些简单问答。这里主要依靠jieba完成对自然语言的分析并转化为cypher语句在知识图谱中进行查询完成。
### 导入库
```
import jieba.posseg as pseg
import jieba
from fuzzywuzzy import fuzz
from py2neo import Graph
```
### 连接neo4j，password替换成自己的密码
```
## 建立neo4j对象，便于后续执行cyphere语句
graph = Graph("http://localhost:7687",auth = ('neo4j','password'))
```
### 匹配问答模板
```
## 用户意图的判断
#设计八类问题的匹配模板
category = ['这部电影主要讲的是什么？','这部电影的主要内容是什么？','这部电影主要说的什么问题？','这部电影主要讲述的什么内容？','这部电影的类型是什么？','这是什么类型的电影']
director = ['这部电影的导演是谁？','这部电影是谁拍的？']
year = ['这部电影是什么时候播出的？','这部电影是什么时候上映的？']
country = ['这部电影是那个国家的？','这部电影是哪个地区的？']
rank = ['这部电影的评分是多少？','这部电影的评分怎么样？','这部电影的得分是多少分？']
comments = ['这部电影的评价人数是多少？','这部有多少人评价过？']
# 设计八类问题的回答模板
categoryResponse = '{}这部电影主要讲述{}'
directorResponse = '{}这部电影的导演为{}'
yearResponse = '{}这部电影的上映时间为{}'
countryResponse = '{}这部电影是{}的'
rankResponse = '{}这部电影的评分为{}'
commentsResponse = '{}这部电影评价的人数为{}人'
# 用户意图模板字典
stencil = {'category':category,'director':director,'year':year,'country':country,'rank':rank,'comments':comments}
# 图谱回答模板字典
responseDict = {'categoryResponse':categoryResponse,'directorResponse':directorResponse,'yearResponse':yearResponse,'countryResponse':countryResponse,'rankResponse':rankResponse,'commentsResponse':commentsResponse}
```
### 分析用户意图并转化为cypher语句
```
# 由模板匹配程度猜测用户意图
def AssignIntension(text):
    '''
    :param text: 用户输入的待匹配文本
    :return: dict:各种意图的匹配值
    '''
    stencilDegree = {}
    for key,value in stencil.items():
        score = 0
        for item in value:
            degree = fuzz.partial_ratio(text,item)
            score += degree
        stencilDegree[key] = score/len(value)

    return stencilDegree

## 问句实体的提取
def getMovieName(text):
    '''
    :param text:用户输入内容
    :return: 输入内容中的电影名称
    '''
    movieName = ''
    jieba.load_userdict('./selfDefiningTxt.txt')
    words =pseg.cut(text)
    for w in words:
        ## 提取对话中的电影名称
        if w.flag == 'lqy':
            movieName = w.word
    return movieName
```
### 实现问答
```
## cyphere语句生成，知识图谱查询，返回问句结果
## py2neo执行cyphere参考文献：https://blog.csdn.net/qq_38486203/article/details/79826028
def SearchGraph(name,stencilDcit = {}):
    '''
    :param name:待查询的电影名称
    :param stencilDcit: 用户意图匹配程度字典
    :return: 用户意图分类，知识图谱查询结果
    '''
    classification = [k for k,v in stencilDcit.items() if v == max(stencilDcit.values())][0]
    ## python中执行cyphere语句实现查询操作
    cyphere = 'match (n:Movie) where n.title = "' + str(name) + '" return n.' + str(classification)
    object = graph.run(cyphere)
    for item in object:
        result = item
    return classification,result

## 根据问题模板回答问题
def respondQuery(movieName,classification,item):
    '''
    :param name: 电影名称
    :param classification: 用户意图类别
    :param item:知识图谱查询结果
    :return:none
    '''
    query = classification + 'Response'
    response = [v for k,v in responseDict.items() if k == query][0]
    print(response.format(name,item))

def main():
    queryText = '肖申克的救赎这部电影的导演是谁？'
    movieName = getMovieName(queryText)
    dict = AssignIntension(queryText)
    classification,result = SearchGraph(name,dict)
    respondQuery(name,classification,result)

if __name__ == '__main__':
    main()
```
