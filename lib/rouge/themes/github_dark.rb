# -*- coding: utf-8 -*- #
# frozen_string_literal: true

module Rouge
  module Themes
    class GithubDark < CSSTheme
      name "github_dark"

      # Primer primitives
      # https://github.com/primer/primitives
      RED_2       = "#ffa198"
      RED_3       = "#ff7b72"
      RED_9       = "#490202"
      ORANGE_2    = "#ffa657"
      ORANGE_3    = "#f0883e"
      GREEN_1     = "#7ee787"
      GREEN_2     = "#56d364"
      GREEN_7     = "#0f5323"
      BLUE_1      = "#a5d6ff"
      BLUE_2      = "#79c0ff"
      PURPLE_2    = "#d2a8ff"
      GRAY_3      = "#8b949e"
      GRAY_4      = "#6e7681"

      FG_SUBTLE   = "#6e7681"
      FG_DEFAULT  = "#e6edf3"
      BG_DEFAULT  = "#0d1117"
      DANGER_FG   = "#f85149"

      style Text,                        fg: FG_DEFAULT, bg: BG_DEFAULT

      style Error,                       fg: DANGER_FG

      style Keyword,                     fg: RED_3
      style Keyword::Constant,
            Keyword::Pseudo,             fg: BLUE_2

      style Name,                        fg: FG_DEFAULT
      style Name::Class,                 fg: ORANGE_3, bold: true
      style Name::Constant,              fg: BLUE_2, bold: true
      style Name::Decorator,
            Name::Function,              fg: PURPLE_2, bold: true
      style Name::Entity,                fg: ORANGE_2
      style Name::Exception,             fg: ORANGE_3, bold: true
      style Name::Label,                 fg: BLUE_2, bold: true
      style Name::Namespace,             fg: RED_3
      style Name::Property,
            Name::Variable,              fg: BLUE_2
      style Name::Tag,                   fg: GREEN_1

      style Literal,
            Literal::String,
            Literal::Number,             fg: BLUE_1
      style Literal::Date,
            Literal::String::Affix,
            Literal::String::Delimiter,
            Literal::String::Escape,
            Literal::String::Heredoc,
            Literal::String::Regex,      fg: BLUE_2

      style Comment,                     fg: GRAY_3, italic: true
      style Comment::Preproc,            fg: GRAY_3, bold: true
      style Comment::Special,            fg: GRAY_3, bold: true, italic: true

      style Operator,                    fg: RED_3, bold: true

      style Generic,                     fg: FG_DEFAULT
      style Generic::Deleted,            fg: RED_2, bg: RED_9
      style Generic::Emph,               italic: true
      style Generic::Error,              fg: RED_2
      style Generic::Heading,            fg: BLUE_2, bold: true
      style Generic::Inserted,           fg: GREEN_2, bg: GREEN_7
      style Generic::Output,
            Generic::Prompt,             fg: GRAY_3
      style Generic::Strong,             bold: true
      style Generic::EmphStrong,         bold: true, italic: true
      style Generic::Subheading,         fg: BLUE_2
      style Generic::Traceback,          fg: RED_3

      style Text::Whitespace,            fg: FG_SUBTLE
    end
  end
end
