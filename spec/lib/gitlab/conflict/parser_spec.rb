require 'spec_helper'

describe Gitlab::Conflict::Parser, lib: true do
  let(:parser) { Gitlab::Conflict::Parser.new }

  describe '#parse' do
    def parse_text(text)
      parser.parse(text, our_path: 'README.md', their_path: 'README.md')
    end

    context 'when the file has valid conflicts' do
      let(:text) do
        <<CONFLICT
module Gitlab
  module Regexp
    extend self

    def username_regexp
      default_regexp
    end

    def project_name_regex
      %r{\A[a-zA-Z0-9][a-zA-Z0-9_\-\. ]*\z}
    end

    def name_regex
      %r{\A[a-zA-Z0-9_\-\. ]*\z}
    end

    def path_regexp
      default_regexp
    end

    def archive_formats_regex
      %r{(zip|tar|7z|tar\.gz|tgz|gz|tar\.bz2|tbz|tbz2|tb2|bz2)}
    end

    def git_reference_regexp
      # Valid git ref regexp, see:
      # https://www.kernel.org/pub/software/scm/git/docs/git-check-ref-format.html
      %r{
        (?!
           (?# doesn't begins with)
           \/|                    (?# rule #6)
           (?# doesn't contain)
           .*(?:
              [\/.]\.|            (?# rule #1,3)
              \/\/|               (?# rule #6)
              @\{|                (?# rule #8)
              \\                  (?# rule #9)
           )
        )
        [^\000-\040\177~^:?*\[]+  (?# rule #4-5)
        (?# doesn't end with)
        (?<!\.lock)               (?# rule #1)
        (?<![\/.])                (?# rule #6-7)
      }x
    end

    protected

    def default_regex
      %r{\A[.?]?[a-zA-Z0-9][a-zA-Z0-9_\-\.]*(?<!\.git)\z}
    end
  end
end
CONFLICT
      end

      let(:lines) do
        parser.parse(text, our_path: 'files/ruby/regex.rb', their_path: 'files/ruby/regex.rb')
      end

      it 'sets our lines as new lines' do
        expect(lines[8..13]).to all(have_attributes(type: 'new'))
        expect(lines[26..27]).to all(have_attributes(type: 'new'))
        expect(lines[56..57]).to all(have_attributes(type: 'new'))
      end

      it 'sets their lines as old lines' do
        expect(lines[14..19]).to all(have_attributes(type: 'old'))
        expect(lines[28..29]).to all(have_attributes(type: 'old'))
        expect(lines[58..59]).to all(have_attributes(type: 'old'))
      end

      it 'sets non-conflicted lines as both' do
        expect(lines[0..7]).to all(have_attributes(type: nil))
        expect(lines[20..25]).to all(have_attributes(type: nil))
        expect(lines[30..55]).to all(have_attributes(type: nil))
        expect(lines[60..62]).to all(have_attributes(type: nil))
      end

      it 'sets consecutive line numbers for index, old_pos, and new_pos' do
        old_line_numbers = lines.select { |line| line.type != 'new' }.map(&:old_pos)
        new_line_numbers = lines.select { |line| line.type != 'old' }.map(&:new_pos)

        expect(lines.map(&:index)).to eq(0.upto(62).to_a)
        expect(old_line_numbers).to eq(1.upto(53).to_a)
        expect(new_line_numbers).to eq(1.upto(53).to_a)
      end
    end

    context 'when the file contents include conflict delimiters' do
      it 'raises UnexpectedDelimiter when there is a non-start delimiter first' do
        expect { parse_text('=======') }.
          to raise_error(Gitlab::Conflict::Parser::UnexpectedDelimiter)

        expect { parse_text('>>>>>>> README.md') }.
          to raise_error(Gitlab::Conflict::Parser::UnexpectedDelimiter)

        expect { parse_text('>>>>>>> some-other-path.md') }.
          not_to raise_error
      end

      it 'raises UnexpectedDelimiter when a start delimiter is followed by a non-middle delimiter' do
        start_text = "<<<<<<< README.md\n"
        end_text = "\n=======\n>>>>>>> README.md"

        expect { parse_text(start_text + '>>>>>>> README.md' + end_text) }.
          to raise_error(Gitlab::Conflict::Parser::UnexpectedDelimiter)

        expect { parse_text(start_text + start_text + end_text) }.
          to raise_error(Gitlab::Conflict::Parser::UnexpectedDelimiter)

        expect { parse_text(start_text + '>>>>>>> some-other-path.md' + end_text) }.
          not_to raise_error
      end

      it 'raises UnexpectedDelimiter when a middle delimiter is followed by a non-end delimiter' do
        start_text = "<<<<<<< README.md\n=======\n"
        end_text = "\n>>>>>>> README.md"

        expect { parse_text(start_text + '=======' + end_text) }.
          to raise_error(Gitlab::Conflict::Parser::UnexpectedDelimiter)

        expect { parse_text(start_text + start_text + end_text) }.
          to raise_error(Gitlab::Conflict::Parser::UnexpectedDelimiter)

        expect { parse_text(start_text + '>>>>>>> some-other-path.md' + end_text) }.
          not_to raise_error
      end

      it 'raises MissingEndDelimiter when there is no end delimiter at the end' do
        start_text = "<<<<<<< README.md\n=======\n"

        expect { parse_text(start_text) }.
          to raise_error(Gitlab::Conflict::Parser::MissingEndDelimiter)

        expect { parse_text(start_text + '>>>>>>> some-other-path.md') }.
          to raise_error(Gitlab::Conflict::Parser::MissingEndDelimiter)
      end
    end

    context 'other file types' do
      it 'raises UnmergeableFile when lines is blank, indicating a binary file' do
        expect { parse_text('') }.
          to raise_error(Gitlab::Conflict::Parser::UnmergeableFile)

        expect { parse_text(nil) }.
          to raise_error(Gitlab::Conflict::Parser::UnmergeableFile)
      end

      it 'raises UnmergeableFile when the file is over 200 KB' do
        expect { parse_text('a' * 204801) }.
          to raise_error(Gitlab::Conflict::Parser::UnmergeableFile)
      end

      it 'raises UnsupportedEncoding when the file contains non-UTF-8 characters' do
        expect { parse_text("a\xC4\xFC".force_encoding(Encoding::ASCII_8BIT)) }.
          to raise_error(Gitlab::Conflict::Parser::UnsupportedEncoding)
      end
    end
  end
end
