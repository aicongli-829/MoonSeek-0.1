///|
test "sha256 known vectors" {
  inspect(
    sha256(b""),
    content="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  inspect(
    sha256(b"abc"),
    content="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "portable path helpers" {
  inspect(clean_relative("/课程\\第一章/"), content="课程/第一章")
  inspect(extension_of("PHOTO.JPEG"), content="jpeg")
  let epoch_offset = filesystem_epoch_offset()
  inspect(month_from_epoch(epoch_offset), content="1970-01")
  inspect(month_from_epoch(epoch_offset + 1789430400L), content="2026-09")
}
