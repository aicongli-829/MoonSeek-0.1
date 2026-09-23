///|
priv struct FacetBucket {
  value : String
  count : Int
}

///|
fn facet_bucket_json(bucket : FacetBucket) -> Json {
  { "value": bucket.value, "count": bucket.count }
}

///|
fn increment_facet(counts : Map[String, Int], value : String) -> Unit {
  if value != "" {
    counts[value] = counts.get(value).unwrap_or(0) + 1
  }
}

///|
fn ranked_facet_buckets(counts : Map[String, Int], limit : Int) -> Array[Json] {
  let buckets : Array[FacetBucket] = []
  for value, count in counts {
    buckets.push({ value, count, })
  }
  buckets.sort_by((left, right) => {
    if left.count > right.count {
      -1
    } else if left.count < right.count {
      1
    } else {
      left.value.compare(right.value)
    }
  })
  let result : Array[Json] = []
  for position, bucket in buckets {
    if position >= limit {
      break
    }
    result.push(facet_bucket_json(bucket))
  }
  result
}

///|
fn size_bucket(size : Int64) -> String {
  if size == 0L {
    "empty"
  } else if size <= 100L * 1024L {
    "tiny"
  } else if size <= 1024L * 1024L {
    "small"
  } else if size <= 100L * 1024L * 1024L {
    "medium"
  } else if size <= 1024L * 1024L * 1024L {
    "large"
  } else {
    "huge"
  }
}

///|
fn search_facets(
  document_indexes : Array[Int],
  documents : Array[Json],
) -> Json {
  let extensions : Map[String, Int] = Map([])
  let categories : Map[String, Int] = Map([])
  let roots : Map[String, Int] = Map([])
  let sizes : Map[String, Int] = Map([])
  for document_index in document_indexes {
    if document_index < 0 || document_index >= documents.length() {
      continue
    }
    let document = documents[document_index]
    let extension = search_text(document, "extension", "")
    increment_facet(
      extensions,
      if extension == "" {
        "none"
      } else {
        extension
      },
    )
    increment_facet(
      categories,
      search_text(document, "category", file_category(extension)),
    )
    increment_facet(roots, search_text(document, "root", ""))
    increment_facet(sizes, size_bucket(search_int64(document, "size", 0L)))
  }
  {
    "extensions": ranked_facet_buckets(extensions, 20).to_json(),
    "categories": ranked_facet_buckets(categories, 20).to_json(),
    "roots": ranked_facet_buckets(roots, 20).to_json(),
    "sizes": ranked_facet_buckets(sizes, 10).to_json(),
  }
}
