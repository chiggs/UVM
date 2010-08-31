//----------------------------------------------------------------------
//   Copyright 2007-2009 Mentor Graphics Corporation
//   All Rights Reserved Worldwide
//
//   Licensed under the Apache License, Version 2.0 (the
//   "License"); you may not use this file except in
//   compliance with the License.  You may obtain a copy of
//   the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in
//   writing, software distributed under the License is
//   distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
//   CONDITIONS OF ANY KIND, either express or implied.  See
//   the License for the specific language governing
//   permissions and limitations under the License.
//----------------------------------------------------------------------

#include <iostream>
#include <map>
#include <string>

#include <sys/types.h>
#include <regex.h>

using namespace std;

const char uvm_re_lead_char = '%';

//----------------------------------------------------------------------
// uvm_re_cache
//
// This class is a wrapper around the linux regex functions.  The
// primary interface is re_match, which attempts to match a string to a
// regular expression.  The regular expression is looked up in the
// cache.  If not present, then the regex is compiled and the compiled
// info is stored in the cache.  If already present then the cached
// compile block is used to perform the match.
//
// uvm_re_cache is a singleton -- the constructor is protected and the
// only way to get an instance is through the static function get()
//----------------------------------------------------------------------
class uvm_re_cache
{
 protected:
  uvm_re_cache() {}
  uvm_re_cache(const uvm_re_cache&) {}
  uvm_re_cache& operator= (const uvm_re_cache&) {}

 private:
  static uvm_re_cache *inst;

 public:
  static uvm_re_cache *get()
  {
    if(inst == NULL)
      inst = new uvm_re_cache;
    return inst;
  }
  
 private:
  typedef map<const string, regex_t*>re_cache_t;
  re_cache_t cache;
  
  //--------------------------------------------------------------------
  // re_compile
  //
  // Compile a regular expression using regcomp().  The resulting data
  // structure that contains the compiled regex is cached.  Future
  // matches for this regex will not require it to be compiled again.
  //--------------------------------------------------------------------
  int re_compile(const string re_str)
  {
    regex_t *rexp;
    int err;
    
    rexp = (regex_t*)malloc(sizeof(regex_t));
    err = regcomp(rexp, re_str.c_str(), REG_EXTENDED);
    if(err != 0)
      return err;
    
    cache[re_str] = rexp;
    return 0;
  }

 public:

  //--------------------------------------------------------------------
  // re_match
  //
  // Match a string to a regular expression.  The regex is first lookup
  // up in the regex cache to see if it has already been compiled.  If
  // so, the compile version is retrieved from the cache.  Otherwise, it
  // is compiled and cached for future use.  After compilation the
  // matching is done using regexec().
  //--------------------------------------------------------------------
  int re_match(const char * re, const char *str)
  {
    regex_t *rexp;
    int err;
    string *re_str;

    re_str = new string(re);

    // Lookup the regexp in the cache
    rexp = cache[*re_str];
    if(rexp == NULL)
    {
      // regexpr not found, let's compile it and add it
      // to the cache
      err = re_compile(*re_str); 
      if(err != 0)
      {
        cout << "regex compiler: invalid glob or regular expression: " << *re_str << endl;
        return err;
      }
      rexp = cache[*re_str];
    }

    delete re_str;
    
    err = regexec(rexp, str, 0, NULL, 0);
    return err;
  }

  //--------------------------------------------------------------------
  // glob_to_re
  //
  // Convert a glob expression to a normal regular expression.
  //--------------------------------------------------------------------
  char *glob_to_re(const char *glob)
  {
    string *temp_re;
    const char *p;
    char * re;

    // safety check.  Glob should never be null since this is called
    // from DPI.
    if(glob == NULL)
      return NULL;

    // Is glob a regex or a glob?  If it has the prefix character
    // regex, otherwise it's a glob

    if(*glob == uvm_re_lead_char)
    {
      // the glob is really a regular expression.  Strip off the 
      // leading character that identifies it as such.
      temp_re = new string(glob + 1);
    }
    else
    {
      // Convert the glob to a true regular expression (Posix syntax)
      temp_re = new string();

      for(p = glob; *p; p++)
      {
        // Replace the glob metacharacters with corresponding regular
        // expression metacharacters.
        switch(*p)
        {
        case '*':
          temp_re->append(".*");
          break;

        case '+':
          temp_re->append(".+");
          break;
          
        case '.':
          temp_re->append("\\.");
          break;
          
        case '?':
          temp_re->push_back('.');
          break;

        case '[':
          temp_re->append("\\[");
          break;

        case ']':
          temp_re->append("\\]");
          break;

        case '(':
          temp_re->append("\\(");
          break;

        case ')':
          temp_re->append("\\)");
          break;
          
        default:
          temp_re->push_back(*p);
          break;
        }
      }
    }

    // temp_re is a C++ string type.  However, we need to return a C
    // style char*. Here we conver the regex string to a char*.
    re = (char*)malloc(temp_re->length() + 1);
    strcpy(re, temp_re->c_str());
    delete temp_re;

    return re;
  }

  //--------------------------------------------------------------------
  // dump_cache
  //
  // Dumps the set of regular expressions stored in the cache
  //--------------------------------------------------------------------
  void dump_cache()
  {
    re_cache_t::iterator i;
    int idx = 0;
    
    cout << " -- re cache dump --" << endl;
    
    for(i = cache.begin(); i != cache.end(); i++)
    {
      cout << idx++ << ": " << i->first << endl;
    }
    
    cout << " -- end --" << endl;
  }

};


// global instance of the regular expression cache.
uvm_re_cache *uvm_re_cache::inst = NULL;
uvm_re_cache *uvm_re = uvm_re_cache::get();


extern "C" {

  // C wrappers around C++ methods.  These C functions can be imported
  // into an SV program

  int uvm_re_match(const char * re, const char *str)
  {
    return uvm_re->re_match(re, str);
  }
  
  void uvm_dump_re_cache()
  {
    uvm_re->dump_cache();
  }

  char * uvm_glob_to_re(const char *glob)
  {
    return uvm_re->glob_to_re(glob);
  }
}
