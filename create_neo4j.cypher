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

MATCH (m:Movie)-[:PRODUCED_IN]->(c:Country)
RETURN m, c;
