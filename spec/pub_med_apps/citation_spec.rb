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

require 'spec_helper'
require 'nokogiri'

module PubMedApps
  describe Citation do

    let(:citation) { Citation.new SpecConst::PMIDS.first }
    let(:xml_no_links) do
      dir = File.dirname(__FILE__)
      fname = 'no_related_citations_elink.xml'
      Nokogiri::XML open File.join(dir, '..', 'test_files', fname)
    end

    describe "::normalize" do
      context "when the query *does* have related citations" do
        before(:each) do
          # resets the scores of 100 related citations to 1...100
          @citation = Citation.new SpecConst::PMIDS.first
          @related_citations = @citation.related_citations
          @related_citations.each_with_index {|related,i| related.score = i+1}
        end

        it "rescales scores on a scale of 0 to 1" do
          @citation.normalize
          normalized_scores = @related_citations.
            map{|related| related.normalized_score}
          decimals=(1..100).to_a.map{|x| (x.to_f/100)}
          expect(normalized_scores).to eq(decimals)
        end
      end
      context "when the query *doesn't* have related citations" do
        it "returns an empty array" do
          allow(EUtils).to receive_messages :elink => xml_no_links
          scores = citation.normalize
          expect(scores).to be_empty
        end
      end
    end

    describe "#new" do
      it "raises an ArgumentError if not passed a PMID" do
        bad_pmid = '456fahehe123'
        err_msg = "#{bad_pmid} is not a proper PMID"
        expect { Citation.new bad_pmid }.to raise_error(ArgumentError,
                                                        err_msg)
      end

      it "raises an ArgumentError if not passed a string" do
        bad_pmid = 17284678
        err_msg = "PubMedApps::Citation.new requires a String"
        expect { Citation.new bad_pmid }.to raise_error(ArgumentError,
                                                        err_msg)
      end

      it "strips whitespace from sloppy user input" do
        bad_pmid = " \t  17284678 \n   \t"
        pmid = Citation.new(bad_pmid).pmid
        expect(pmid).to eq '17284678'
      end
    end

    describe "#get_info" do
      context "with a PMID that doesn't have a matching UID in NCBI" do
        before :all do
          @citation = Citation.new "0"
        end

        it "shouldn't raise OpenURI::HTTPError" do
          expect { @citation.get_info }.not_to raise_error
        end

        it "sets @pmid to nil" do
          expect(@citation.pmid).to be nil
        end

        it "sets @score to nil" do
          expect(@citation.score).to be nil
        end

        it "sets @abstract to nil" do
          expect(@citation.abstract).to be nil
        end

        it "sets @title to nil" do
          expect(@citation.title).to be nil
        end

        it "sets @pub_date to nil" do
          expect(@citation.pub_date).to be nil
        end

        it "sets @references to nil" do
          expect(@citation.references).to be nil
        end
      end

      context "after calling #get_info, let's spec the instance methods" do
        before :all do
          @citation = Citation.new SpecConst::PMIDS.first
          @citation.get_info
        end

        describe "#pmid" do
          it "returns the original pmid" do
            expect(@citation.pmid).to eq SpecConst::PMIDS.first
          end
        end

        describe "#abstract" do
          it "returns the original abstract" do
            expect(@citation.abstract).to eq SpecConst::ABSTRACTS.first
          end
        end

        describe "#pub_date" do
          it "returns the original pub_date" do
            expect(@citation.pub_date).to eq SpecConst::PUB_DATES.first
          end
        end

        describe "#score" do
          it "returns the original score" do
            expect(@citation.score).to eq 0
          end
        end

        describe "#title" do
          it "returns the original title" do
            expect(@citation.title).to eq SpecConst::TITLES.first
          end
        end

        describe "#references" do
          it "returns an array of Citations that this Citation cites" do
            expect(@citation.references). to match_array SpecConst::REFERENCES.first
          end
        end
      end
    end

    describe "#related_citations" do
      context "when @pmid is nil (No PMID found)" do
        before :each do
          @bad_citation = Citation.new "0"
        end

        context "when #get_info has already been called" do
          it "returns an empty array" do
            @bad_citation.get_info
            expect(@bad_citation.related_citations).to eq []
          end
        end

        context "when #get_info hasn't already been called" do
          it "returns an empty array" do
            # the elink xml will look like xml_no_links
            expect(@bad_citation.related_citations).to eq []
          end
        end
      end


      context "when @pmid is not nil (ie the PMID is okay)" do
        context "when the citation *does* have related citations" do
          before :each do
            dir = File.dirname(__FILE__)
            fname = 'test.xml'
            xml_with_links =
              Nokogiri::XML open File.join(dir, '..', 'test_files',
                                           fname)

            allow(EUtils).to receive_messages :elink => xml_with_links
            @related_citations = citation.related_citations
          end

          it "returns an array with related citations" do
            pmids = @related_citations.map { |id| id.pmid }
            expect(pmids).to eq SpecConst::PMIDS
          end

          it "the array is filled with Citations" do
            all_citations = @related_citations.all? do |id|
              id.instance_of? Citation
            end
            expect(all_citations).to be true
          end

          it "adds the score to the related Citation objects" do
            scores = @related_citations.map { |id| id.score }
            expect(scores).to eq SpecConst::SCORES
          end

          it "adds the title to the related Citation objects" do
            titles = @related_citations.map { |id| id.title }
            expect(titles).to eq SpecConst::TITLES
          end

          it "adds the abstract to the related Citation objects" do
            abstracts = @related_citations.map { |id| id.abstract }
            expect(abstracts).to eq SpecConst::ABSTRACTS
          end

          it "adds the pub_date to the related Citation objects" do
            pub_dates = @related_citations.map { |id| id.pub_date }
            expect(pub_dates).to eq SpecConst::PUB_DATES
          end

        end

        context "when the citation has *no* related citations" do
          before(:each) do
            allow(EUtils).to receive_messages :elink => xml_no_links
          end

          it "returns an empty array if there are no related citations" do
            expect(citation.related_citations).to eq []
          end
        end
      end
    end

    shared_examples "for the query node" do
      it "has a PMID" do
        expect(json).
          to include %Q{"PMID":"#{SpecConst::PMIDS.first}"}
      end

      it "has an abstract" do
        expect(json).
          to include %Q{"abstract":"#{SpecConst::ABSTRACT_1}"}
      end

      it "has a title" do
        expect(json).
          to include %Q{"title":"#{SpecConst::TITLE_1}"}
      end
    end

    describe "#to_json" do
      context "when the query *doesn't* have related citations" do
        before(:each) do
          allow(EUtils).to receive_messages :elink => xml_no_links
          @queryjson=citation.to_json
        end

        include_examples "for the query node" do
          let(:json) { @queryjson }
        end

        it "returns a properly formatted json string" do
          expect{JSON.parse @queryjson}.to_not raise_error
        end

        it "does not return any links" do
          parsed = JSON.parse @queryjson
          expect(parsed["links"]).to be_empty
        end
      end

      context "when the query *does* have related citations" do
        before :each do
          dir = File.dirname(__FILE__)
          fname = 'test.xml'
          xml_with_links =
            Nokogiri::XML open File.join(dir, '..', 'test_files',
                                         fname)

          allow(EUtils).to receive_messages :elink => xml_with_links
          @queryjson=citation.to_json
        end

        include_examples "for the query node" do
          let(:json) { @queryjson }
        end

        it "returns a properly formatted json string" do
          expect{JSON.parse @queryjson}.to_not raise_error
        end

        it "returns a json containing an array of nodes" do
          parsed = JSON.parse @queryjson
          expect(parsed["nodes"]).to_not be_empty
        end

        it "returns a json containing an array of links" do
          parsed = JSON.parse @queryjson
          expect(parsed["links"]).to_not be_empty
        end
      end
    end
  end
end
