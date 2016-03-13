# Copyright 2015 Ryan Moore
# Contact: moorer@udel.edu
#
# This file is part of PubMedApps.
#
# PubMedApps is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# PubMedApps is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with PubMedApps.  If not, see <http://www.gnu.org/licenses/>.

require 'open-uri'
require 'json'



module PubMedApps

  # Provides methods for getting related pubmed citations.
  class Citation
    # Normalizes scores on a scale of 0 to 1
    #
    # As a PubMedApps web designer
    #   I would like to normalize scores
    #   So that I can sane branch lengths in my PubMed Flower
    #
    # @param citations [Array<Citation>] an array of Citation
    #   elements, likely the return value from a call to
    #   #related_citations
    #
    # @return [Array<Citation>] normalized scores
    def normalize
      scores = related_citations.map { |citation| citation.score }
      @related_citations.each do |citation|
        citation.normalized_score = citation.score / scores.max.to_f
      end
      @related_citations
    end

    attr_accessor :pmid, :score, :abstract, :title, :pub_date, :references,
    :normalized_score

    # @raise [ArgumentError] if passed improper PMID
    #
    # @raise [ArgumentError] if not passed a String
    def initialize(pmid)
      unless pmid.kind_of? String
        raise(ArgumentError,
              "PubMedApps::Citation.new requires a String")
      end

      pmid.strip!

      if pmid.match /^[0-9]+$/
        @pmid = pmid
      else
        err_msg = "#{pmid} is not a proper PMID"
        raise ArgumentError, err_msg
      end

      @score = 0
      @normalized_score = 0
    end

    # Only fetch the related citations if they are needed.
    #
    # The first call to related_citations stores the array in the
    # instance variable, and all subsequent calls just return that
    # value.
    #
    # @return [Array<Citation>] an array of related Citations
    def related_citations
      @related_citations ||= fetch_related_citations
    end

    # Convert related citations into json format
    #
    # First, verifies that the @related_citations is instantiated
    # Second, checks that all @related_citations are Citations
    # Then converts query node and @related_citations to json
    #
    #
    # @return [JsonString] json formatted related citations
    def to_json
      related_citations
      normalize
      citations=@related_citations

      # get info if needed
      get_info unless @abstract

      nodes = [{:PMID => @pmid,
                :abstract => @abstract,
                :title => @title}.to_json]
      links = []

      unless citations.empty?
        citations.each_with_index do |rec,i|
          nodes << {:PMID=>rec.pmid, }.to_json
          links << {:source=>0,
            :target=>i+1,
            :value=>rec.normalized_score}.to_json
        end
      end
      "{\"nodes\":[#{nodes.join(',')}],\"links\":[#{links.join(',')}]}"
    end

    # Gets the title, abstract and pub_date from EUtils.
    #
    # To avoid the EUtils overhead, call this only for the very first
    # Citation given by the user. The info for the related PMIDs will
    # be propagated by the #related_citations method.
    #
    # @note This methods pings NCBI eutils once.
    def get_info
      begin
        efetch_doc = EUtils.efetch @pmid
        @title = EUtils.get_titles(efetch_doc).first
        @abstract = EUtils.get_abstracts(efetch_doc).first
        @pub_date = EUtils.get_pub_dates(efetch_doc).first
        @references = EUtils.get_references(efetch_doc)
      rescue OpenURI::HTTPError => e
        @pmid, @title, @abstract, @pub_date, @references, @score = nil
        @citations = nil
      end
    end

    private

    # citations is an array of Citaiton objects
    #
    # @todo Change array of objects in place?
    #
    # @param citations [Arrary<Citation>] An array of Citation objects
    #
    # @param scores [Array<String>] An array of strings with the
    #   scores
    def add_scores citations, scores
      citations.zip(scores).each do |citation, score|
        citation.score = score
      end
      citations
    end

    def add_titles citations, titles
      citations.zip(titles).each do |citation, title|
        citation.title = title
      end
      citations
    end

    def add_abstracts citations, abstracts
      citations.zip(abstracts).each do |citation, abstract|
        citation.abstract = abstract
      end
      citations
    end

    def add_pub_dates citations, pub_dates
      citations.zip(pub_dates).each do |citation, pub_date|
        citation.pub_date = pub_date
      end
      citations
    end

    # Returns an array of Citations related to the pmid attribute
    #
    # Only takes the PMIDs in the LinkSetDb that contians the LinkName
    #   with pubmed_pubmed. Will return an empty array if there are no
    #   related citations, or if the @pmid doesn't have a matching UID
    #   in NCBI.
    #
    # @note This methods pings NCBI eutils twice.
    #
    # @todo instead of using .first, could this be done with xpath?
    #
    # @return [Array<Citation>] an array of Citations
    def fetch_related_citations
      # @pmid will be nil if get_info was called and the PMID didn't
      # have a matching UID in NCBI
      return [] if @pmid.nil?

      doc = EUtils.elink @pmid
      pm_pm = doc.css('LinkSetDb').first

      # should be nil if there are no related citations OR get_info
      # was NOT called and the PMID didn't have a matching UID in NCBI
      return [] if pm_pm.nil?

      name = pm_pm.at('LinkName').text

      unless  name == 'pubmed_pubmed'
        abort("ERROR: We got #{name}. Should've been pubmed_pubmed. " +
              "Possibly bad xml file.")
      end

      citations = get_citations pm_pm
      scores = get_scores pm_pm

      unless citations.count == scores.count
        abort("ERROR: different number of Citations and scores when " +
              "scraping xml")
      end

      populate_related_citations citations, scores
    end

    # Get the citations from the Nokogiri::XML
    def get_citations pm_pm
      pm_pm.css('Link Id').map do |elem|
        Citation.new elem.text
      end
    end

    # Get the scores from the Nokogiri::XML
    def get_scores pm_pm
      pm_pm.css('Link Score').map { |elem| elem.text.to_i }
    end

    # Add the info from the EFetch for each citation, eg title,
    #   abstract, etc
    def populate_related_citations citations, scores
      related_pmids = citations.map { |citation| citation.pmid }
      efetch_doc = EUtils.efetch *related_pmids
      titles = EUtils.get_titles efetch_doc
      abstracts = EUtils.get_abstracts efetch_doc
      pub_dates = EUtils.get_pub_dates efetch_doc

      citations = add_scores citations, scores
      citations = add_titles citations, titles
      citations = add_abstracts citations, abstracts
      citations = add_pub_dates citations, pub_dates

      citations
    end
  end
end
