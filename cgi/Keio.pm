package Keio;
use vars qw(@ISA @EXPORT @EXPORT_OK);

use strict;
use warnings;
use utf8;
use Encode;
binmode(STDOUT, ':encoding(UTF-8)');

sub new
{
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  my $crms = $args{crms};
  die "Keio module needs CRMS instance." unless defined $crms;
  $self->{crms} = $crms;
  return $self;
}

sub Tables
{
  return ['T_BOOK_DM', 'dbo_T_BOOK', 'dbo_T_aid', 'dbo_T_aid_set_B',
          'dbo_T_aid_set_E', 'dbo_T_aid_set_F', 'dbo_T_aid_set_H',
          'dbo_T_aid_set_J', 'dbo_T_aid_set_M', 'dbo_T_aid_set_P',
          'dbo_T_aut', 'dbo_T_aut_hld', 'dbo_T_code'];
}

sub TableQuery
{
  my $self  = shift;
  my $table = shift;
  my $page  = shift || 0;

  my $dbh = $self->{crms}->db->dbh;
  my $sql = 'SELECT * FROM `'. $table. '` WHERE 1=0';
  my $sth = $dbh->prepare($sql);
  $sth->execute();
  my @fields = @{$sth->{NAME}};
  @fields = map {Encode::decode('UTF-8', $_, Encode::FB_CROAK);} @fields;
  my $offset = $page * 50;
  $sql = 'SELECT * FROM `'. $table. "` LIMIT 50 OFFSET $offset";
  my $ref = $self->{crms}->SelectAll($sql);
  $sql = 'SELECT COUNT(*) FROM `'. $table. '`';
  my $total = $self->{crms}->SimpleSqlGet($sql);
  my $pages = POSIX::ceil($total / 50);
  my $ret = {'fields' => \@fields,
             'data'   => $ref,
             'total'  => $total,
             'pages'  => $pages};
  return $ret;
}

my $QUERIES = {'dbo_T_aut.stat' => 'SELECT DISTINCT stat FROM dbo_T_aut WHERE stat IS NOT NULL',
               'Author to HT volumes' => 'SELECT a.aut_id,a.aut_nam,a.aut_year,a.stat,a.resu,CONCAT("keio.",b.bookid) FROM dbo_T_aut_hld ah INNER JOIN dbo_T_aut a ON ah.aut_id=a.aut_id INNER JOIN dbo_T_BOOK b ON ah.hld_id=b.hld_id',
              };

sub Queries
{
  my $self = shift;

  return keys %$QUERIES;
}

sub Query
{
  my $self  = shift;
  my $name  = shift;
  my $page  = shift || 0;

  my $dbh = $self->{crms}->db->dbh;
  my $sql = $QUERIES->{$name};
  my $offset = $page * 50;
  $sql .= ' LIMIT 50 OFFSET '. $offset;
  my $sth = $dbh->prepare($sql);
  $sth->execute();
  my @fields = @{$sth->{NAME}};
  @fields = map {Encode::decode('UTF-8', $_, Encode::FB_CROAK);} @fields;
  my $ref = [];
  while (my @data = $sth->fetchrow_array())
  {
    push @$ref, \@data;
  }
  $sql = $QUERIES->{$name};
  $sql =~ s/SELECT.+?FROM/SELECT COUNT(*) FROM/;
  my $total = $self->{crms}->SimpleSqlGet($sql);
  my $pages = POSIX::ceil($total / 50);
  my $ret = {'fields' => \@fields,
             'data'   => $ref,
             'total'  => $total,
             'pages'  => $pages};
  return $ret;
}

my $DICTIONARY = { '添付番号' => 'Attachment Number',
                   '著者名' => 'Author Name',
                   '総合担当者' => 'Contact Person',
                   '聞蔵' => '(聞蔵IIビジュアル) Kikuzō II bijuaru for libraries',
                   '読売' => '(読売新聞) Yomiuri Shimbun newspaper',
                   '朝日' => '(朝日新聞) Asahi Shimbun newspaper',
                   '皓星社' => 'Koseisha Database',
                   '関連する地域名（東京都は不要）' => 'Related area name (Tokyo not required) (?)',
                   '県別辞典' => 'Prefecture dictionary',
                   '添付無し＝0、添付有り＝1、判明＝3、調査不要＝4、外人＝空白' => 'Not attached = 0, attached = 1, found = 3, investigation unnecessary = 4, foreigner = blank',
                   '備考' => 'Notes',
                   '生没年 ' => 'Death year',
                   '調査不要' => 'No investigation required',
                   '近デジ' => '(近代デジタルライブラリー) Modern Digital Library (?)',
                   '裁定' => 'Determination',
                   '無し' => 'None',
                   '最初に登場する本（他にもある）' => 'First book to appear (among others)',
                   '許諾' => 'License',
                   '満了' => 'Expiration',
                   '漢籍' => 'Chinese book',
                   '判明' => 'Identified',
                   '調査不可能' => 'Impossible to investigate',
                   '望み薄' => 'Unlikely',
                   '次回調査' => 'Next investigation',
                   '団体・政府' => 'Group / Government',
                   '変名' => 'Unusual name',
                   '保護期間中' => 'Still in copyright',
                   '版違(満了)' => 'Mismatch (expired)',
                   '版違(裁定)' => 'Mismatch (determination)',
                   '版違(許諾)' => 'Mismatch (license)',
                   '公開' => 'Release',
                   '非公開' => 'Private',
                   '調査中' => 'Still investigating',
                   '調査中止' => 'Investigation cancelled',
                   '出版年' => 'Year of publication',
                   '検討中' => 'Under review',
                   '著作権保護中' => 'Protected by copyright',
                   '個人情報' => 'Personal information',
                   '大破損' => 'Major damage',
                   '別名' => 'Alias',
                   '翻訳' => 'Translation',
                   '多数の著者' => 'Many authors',
                   '吉田' => 'Yoshida (surname)',
                   '内堀' => 'Uchibori (surname)',
                   '佐藤' => 'Sato (surname)',
                   '北山' => 'Kitayama (surname)',
                   '吉田調査中' => 'Yoshida (surname) investigating',
                   '未設定フラグ' => 'Unset flag (??)',
                   '人物レファレンス辞典' => 'Person Reference Encyclopedia',
                   '近代日本の先駆者' => 'Encyclopedia of Japanese Pioneers',
                   '海を越えた' => 'Beyond the Sea (reference book??)',
                   '公式URL集' => 'Official URL Collection',
                   '著書・著者情報' => 'Author / Author Information',
                   '近代デジタルライブラリー' => 'Modern Digital Library',
                   '日本人名大辞典' => 'Japanese Name Dictionary',
                   '調査保留' => 'Survey pending'
                 };

sub Translation
{
  my $self = shift;
  my $word = shift;

  return $DICTIONARY->{$word} || '';
}

1;
