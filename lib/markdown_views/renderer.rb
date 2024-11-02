module MarkdownViews
  class Renderer
    class << self

      def render(template)
        out = template.to_s
        out = strip_comments(out) if MarkdownViews.strip_comments
        out = render_md(out)
        out = strip_comments(out) if MarkdownViews.strip_comments
        out.html_safe
      end

      # remainder all considered private

      def render_md(input)
        doc = Commonmarker.parse(input, options: {
          extension: MarkdownViews.extensions,
          parse: MarkdownViews.parsing_opts,
        })

        if MarkdownViews.transformers.include? :code_blocks
          code_blocks = transform_code_blocks(doc)
        end

        out = doc.to_html(
          options: {
            extension: MarkdownViews.extensions,
            render: MarkdownViews.rendering_opts,
          },
          plugins: MarkdownViews.plugins
        )
        code_blocks&.each do |uuid, cb|
          out.sub! uuid, cb
        end
        out
      end

      def rouge_formatter
        MarkdownViews.rouge_opts[:formatter] || Rouge::Formatters::HTML.new
      end

      # removes single & multi-line comments
      #   if any content besides comment & whitespace is on same line(s), strips just the comment.
      #   if no other content, strips the lines & whitespace too.
      def strip_comments(input)
        # ^[ \t]*(<!--.*?-->)++[ \t]*\r?\n    lines with just comments
        # |                                   or
        # <!--.*?-->                          comments on lines with other content
        #
        # ^                 start of line
        # [ \t]*            optional spaces or tabs
        # (<!--.*?-->)++
        #   <!--            start of html comment
        #   .*?             any char, incl linefeed (for multi-line comments)
        #                     lazy (non-greedy): *?
        #   -->             end of html comment
        #   ++              possessive match - prevents a match across comment boundaries
        #                     ie: prevent matching this: <!-- a --> keep <!-- b -->
        #                     explanation: initially .*? will refuse to match --> because it's
        #                       non-greedy. but, in search of pre/post whitespace, the regex engine
        #                       could backtrack and ask .*? to match an --> as long as there's
        #                       another --> later. possessive disables the backtracking.
        #                     can combine <!-- a --><!-- b --> into one match, which is of no harm.
        # [ \t]*            optional spaces or tabs
        # \r?\n             end of line (either unix or windows style)
        input.gsub(/^[ \t]*(<!--.*?-->)++[ \t]*\r?\n|<!--.*?-->/m, '')
      end

      def transform_code_blocks(doc)
        code_blocks = {}
        doc.walk do |node|
          next unless node.type == :code_block
          next if node.fence_info == ''

          lang = node.fence_info
          code = node.string_content
          lexer = Rouge::Lexer.find(lang) || Rouge::Lexers::PlainText
          html = rouge_formatter.format(lexer.lex code).rstrip
          if MarkdownViews.rouge_opts[:wrap]
            html = %Q{<pre lang="#{lang.gsub(/[^a-z0-9_-]/,'')}"><code class="rouge-highlight">#{html}</code></pre>}
          end

          uuid = SecureRandom.uuid
          code_blocks[uuid] = html
          new_node = Commonmarker::Node.new(:text, content: "#{uuid}\n")
          node.replace new_node
        end
        code_blocks
      end

    end
  end
end
