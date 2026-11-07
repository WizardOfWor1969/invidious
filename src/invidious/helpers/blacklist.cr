module Invidious::Blacklist
  extend self

  # Returns a new array with all items that belong to a channel in the
  # user's blacklist removed.
  #
  # This must NOT mutate the input array: some inputs (e.g. the shared
  # popular-videos array) are global state shared between requests.
  #
  # Works on any item type that has a `ucid` (SearchVideo, SearchChannel,
  # SearchPlaylist, ChannelVideo, PlaylistVideo, ...). Items without a
  # `ucid` (e.g. ProblematicTimelineItem) are always kept.
  def filter(items, user : Invidious::User?)
    return items if user.nil?
    return items if user.blacklist.empty?

    blacklist = user.blacklist
    return items.reject { |item| item.responds_to?(:ucid) && blacklist.includes?(item.ucid) }
  end

  # Same as `filter`, for watch-page related videos
  # (Array(Hash(String, String))).
  def filter_related(related : Array(Hash(String, String)), user : Invidious::User?)
    return related if user.nil?
    return related if user.blacklist.empty?

    blacklist = user.blacklist
    return related.reject { |rv| (ucid = rv["ucid"]?) && blacklist.includes?(ucid) }
  end
end
