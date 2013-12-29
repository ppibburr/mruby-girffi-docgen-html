class DocGen
  module Generator
    class HTML < Base
      HEADER = "<html>
  <head>
    <link rel=\"stylesheet\" type=\"text/css\" href=style.css>
    <script src=data.js></script>
  </head>"
  
      FOOTER = "    
    <script src=tool.js>
    </script> 
  </body> 
</html>\n\n"
    
      attr_reader :namespace, :version
      def initialize ns, version = nil
        super(ns)
        @version = version
        
        @topnav = "<div class=top_nav><a href=#{namespace[:name]}.html>#{namespace[:name]}::</a><form>
    <select id=interfaces></select>
  </form></div>\n "        
      end
      
      def generate_ifaces_summary()
        return if (namespace[:interfaces] ||= []).empty?
        puts "<div id=ifaces_summary_header class=summary_header><b>Interfaces</b><small id=ifaces_summary_toggle>(Collapse)</small></div>"
        puts "<div id=ifaces_summary class=summary>"
        
        namespace[:interfaces].each do |i|
          t = i.is_a?(DocGen::Output::Class) ? "Class" : "Module"
      
          puts "<div>&nbsp;&nbsp;(#{t}) <a href=#{namespace[:name]}_#{i[:name]}.html><b>#{i[:name]}</b></a>&nbsp;&nbsp;</div>"
        end
        
        puts "</div>"
      end
      
      def generate()
        q = {}
        q[:interfaces] = {}
        q[:functions]  = {}
        @namespace[:functions].each do |f|
          q[:functions][f.name] = !!f[:method]
        end
        
        q[:name] = namespace[:name]
        namespace[:interfaces].each do |i|
          generate_iface(i)
          
          h = q[:interfaces][i[:name]] = {}
          h[:is_class] = !!i.is_a?(DocGen::Output::Class)
          
          h[:functions] = {}

          i[:functions].each do |f|
            h[:functions][f[:name]] = !!f[:method]
          end
          
          h[:signals] = []
          (i[:signals]||=[]).each do |s|
            h[:signals] << s[:name]
          end          
        end
        
        GLib::File.set_contents("data.js", "var namespace="+JSON::stringify(q))
        
        @buffer = []
        
        puts HEADER+"\n  <body id=#{namespace[:name]} class=namespace>#{@topnav}"
        puts "<h2>Module: #{namespace[:name]}</h2>"
        
        generate_constants_summary()     
        generate_enums_summary()   
        generate_enums_summary(:flag)                     
        generate_ifaces_summary()
        
        generate_enums_details()       
        generate_enums_details(:flag)                 
        generate_method_summary(namespace,:class)
        generate_methods_details(namespace,:class)    
                        
        puts FOOTER
        
        file = "#{namespace[:name]}.html"
        
        GLib::File.set_contents file,@buffer.join("\n")         
      end
      
      def puts s
        @buffer << s
      end
      
      def generate_constants_summary()
        return if (namespace[:constants]||=[]).empty?      
        puts "<div id=constants_summary_header class=summary_header><b>Constants</b><small id=constants_summary_toggle>(Collapse)</small></div>"
        puts "<div class=constant_summary id=constants_summary>"
        namespace[:constants].each do |c|
          if c[:type] == :constant
            generate_constant_summary(c)
            puts "<br>"
          end
        end
        puts "</div>"
      end
 
      def generate_enums_summary(t=:enum)
        return unless (namespace[:constants]||=[]).find do |c| c[:type] == t end      
        puts "<div id=#{t}s_summary_header class=summary_header><b>#{t.to_s.capitalize}s</b><small id=#{t}s_summary_toggle>(Collapse)</small></div>"
        puts "<div class=enum_summary id=#{t}s_summary>"
        
        namespace[:constants].each do |c|
          if c[:type] == t
            generate_enum_summary(c,t)
          end
        end
        puts "</div>"
      end   
      
      def generate_enums_details(t=:enum)
        return unless (namespace[:constants]||=[]).find do |c| c[:type] == t end
        puts "<div id=#{t}s_details_header class=details_header><b>#{t.to_s.capitalize}s Details</b><small id=#{t}s_details_toggle>(Collapse)</small></div>"
        puts "<div class=enum_details id=#{t}s_details>"
        namespace[:constants].each do |c|
          if c[:type] == t
            generate_enum_details(c,t)
            puts "<br>"
          end
        end
        puts "</div>"
      end      
      
      def generate_signal_summary(i)
        if !(sigs = i[:signals] ||= []).empty?
          puts "    <div id=signals_summary_header class=summary_header><b>Signals</b>#{generate_toggle("signals_summary")}</div>"
          puts "    <div class=summary id=signals_summary>"
          
          sigs.each do |s|
            generate_callable_summary(s,:signal)
          end
          
          puts "</div>"
        end      
      end
      
      def generate_type_link(t)
        link = t.to_s.split("::")[0] == namespace[:name]
        q = link ? "<a href=#{t.to_s.split("::").join("_")}.html>#{t}</a>" : t      
      end
      
      def extract_type t,mklink=false
        block = false
      
        if ary=t[:array]
          at=ary.types.map do |tt|
            if mklink
              rt=generate_type_link(tt[:name].to_s)
            else
              rt = tt[:name].to_s           
            end
          end
          
          rt = "Array&lt;#{at.join(", ")}&gt;"
        elsif t[:block]
          block = true
        else
          if mklink
            rt=generate_type_link(t[:type][:name].to_s)
          else
            rt = t[:type][:name].to_s           
          end
        end
        
        return rt,block      
      end
      
      def extract_callable_signature(c,type=instance)
        ntn = "*" if type == :signal
        ntn = "-" if type == :instance
        ntn = "+" if type == :class   

        rt,_ = extract_type(c.returns)       
         
        q = c[:returns][:array] ? extract_type(c.returns,true)[0] : generate_type_link(rt)
        
        block = false
        bool= false
        ala=[]
        al = (c.arguments ||= []).map do |a|
          tt,bool=extract_type(a,true)
          block = a if bool
          ala << tt
          a[:name]
        end
        
        if bool
          al.pop
          ala.pop
        end
        
        if !al.empty? and type == :signal;
          al = "|#{al.join(", ")}|"
        else
          al = al.join(", ")
        end
        
        return ntn,rt.to_s,al,q,ala,block      
      end
      
      def generate_block_summary blk
        al = (blk[:parameters] ||= []).map do |a|
          a[:name]
        end.join(", ")
        
        "{|#{al}| ... }"
      end
      
      def generate_callable_summary(c, type=:instance)
        ntn,q,al,q_link,ala,block = extract_callable_signature(c,type)

        has_block = nil
        if block
          has_block = " "+generate_block_summary(block[:block])
        end
        
        puts "<div>&nbsp;&nbsp;<a href=##{type}_#{c.name}>#{ntn} (#{q}) <b>#{c.name}</b>(#{al})#{has_block}</a>&nbsp;&nbsp;</div>" if type != :signal
        puts "<div>&nbsp;&nbsp;<a href=##{type}_#{c.name}>#{ntn} (#{q}) <b>\"#{c.name}\"</b> {#{al} ... }</a>&nbsp;&nbsp;</div>" if type == :signal            
        puts "<div> #{c[:symbol]} </div>" if type != :signal
        puts "<div> true_stops_emit? #{c[:true_stops_emit]}</div>" if type == :signal
      end

      def generate_callable_details(c,type=:instance)
        ntn, q, al, q_link, ala, block = extract_callable_signature(c,type)

        has_block = nil
        if block
          has_block = " "+generate_block_summary(block[:block])
        end

        puts "<div class=signature>&nbsp;&nbsp;#{ntn} (#{q_link}) <b><a name=\"#{type}_#{c.name}\">#{c.name}</a></b>(#{al})#{has_block}&nbsp;&nbsp;</div>" if type != :signal
        puts "<div class=signature>&nbsp;&nbsp;#{ntn} (#{q_link}) <b>\<a name=\"#{type}_#{c.name}\">#{c.name}\"</a></b> {#{al} ... }&nbsp;&nbsp;</div>" if type == :signal 
        
        puts "<div class=detail>"
        
        if !(ala).empty?
          puts "<div class=parameters_header><b>parameters:</b><br></div>"
          
          ala.each_with_index do |a,idx|
            puts "<li class=param> (#{a}) <b>#{c[:arguments][idx][:name]}</b> #{c[:arguments][idx][:description]} </li>"
          end 
          
          puts "<br>"
        end

        if block
          puts "<div class=parameters_header><b>yieldparameters:</b><br></div>"
          (block[:block][:parameters]||=[]).each do |a|
            puts "<li class=param> (#{extract_type(a,true)[0]}) <b>#{a[:name]}</b> #{a[:description]}</li>"
          end
          puts "<br><div class=parameters_header><b>yieldreturns:</b><br></div>"
          puts "<li class=return>(#{extract_type(block[:block][:returns],true)[0]}) #{block[:block][:returns][:description]}</li>"
          puts "<br><br>"          
        end
        
        puts "<div class=returns_header><b>returns:</b><br></div>"
        puts "<li class=return> (#{q_link}) #{c[:returns][:description]} </li>"                  
        puts "</div>"
      end
      
      def generate_toggle(q)
        "<small id=#{q}_toggle>(Collapse)</small>"
      end
      
      def generate_signals_details(i)
        if !(sigs = i[:signals] ||= []).empty?
          puts "    <div id=signals_details_header class=details_header><b>Signals Details</b>#{generate_toggle("signals_details")}</div>"
          puts "    <div class=details id=signals_details>"
          sigs.each do |s|
            generate_callable_details(s,:signal)
          end
          puts "</div>"
        end
      end
      
      def generate_methods_details(i,type=:instance)
        if !(meths=(i[:functions] ||= []).find_all do |f| type==:instance ? f[:method] : !f[:method] end).empty?
          puts "    <div id=#{type}_methods_details_header class=details_header><b>#{type.capitalize} Methods Details</b>#{generate_toggle("#{type}_methods_details")}</div>"
          puts "    <div class=details id=#{type}_methods_details>"
          meths.each do |m|
            generate_callable_details(m,type)
          end
          puts "</div>"
        end
      end      
      
      def generate_constant_summary z
        link = z.class.to_s.split("::")[0] == namespace[:name]
        q = link ? "<a href=#{z.class.split("::").join("_")}.html>#{z.class}</a>" : "#{z.class}"
        v = z.class == String ? "\"#{z.value}\"" : z.value
        puts "<div class=summary_item>&lt (#{q}) <b>#{z.name}</b> = #{v} &nbsp;&nbsp;</div>"
      end
      
      def generate_enum_details z,t=:enum
        puts "<div class=enum><div class=enum_root><a name=enum_#{z.name}>&nbsp;&nbsp;&gt (Class) <b>#{z.name}</b>&nbsp;&nbsp;</a></div><br>"
        z[t].values.each_pair do |n,v|
          puts "<li class=enum_member>&lt (Integer) <b>#{n.upcase}</b> = #{v} &nbsp;&nbsp;</li>"
        end
        puts "</div>"
      end      
      
      def generate_enum_summary z,t=:enum
        puts "<div class=enum_root><a href=#enum_#{z.name}>&nbsp;&nbsp;&gt (Class) <b>#{z.name}</b>&nbsp;&nbsp;</a></div>"
      end         
      
      def generate_method_summary(i,type=:instance)
        cfuncs = i[:functions].find_all do |f| 
          type == :instance ? f[:method] : !f[:method] 
        end
        
        if !cfuncs.empty?
          puts "    <div><div id=#{type}_methods_summary_header class=summary_header><span><b>#{type.capitalize} Methods Summary</b></span>#{generate_toggle("#{type}_methods_summary")}</div>"
          puts "    <div class=summary id=#{type}_methods_summary>"
          
          cfuncs.each do |f|
            generate_callable_summary(f,type)
          end
          
          puts "</div></div><br>"
        end       
      end
      
      def generate_iface i
        @buffer = []
        
        puts HEADER+"\n  <body id=#{i[:name]} class=#{i.is_a?(DocGen::Output::Class) ? "class" : "iface"}>#{@topnav}"

        cls = nil
        if i.is_a?(DocGen::Output::Class)
          cls=true
          puts "<h2>Class: #{namespace[:name]}::#{i[:name]}</h2>"
        elsif i.is_a?(DocGen::Output::IFace)
          puts "<h2>Module: #{namespace[:name]}::#{i[:name]}</h2>"
        end
                       
        sc = i[:superclass]
        
        if sc
          puts "    <div class=summary_header id=inherits_summary_header><b>Inherits</b>:"
          link = sc.split("::")[0] == namespace[:name]
        
          puts "    <div class=item>#{link ? "<a href=#{sc.split("::").join("_")}.html>#{sc}</a>" : "#{sc}"}</div><small id=inherits_summary_toggle>(Collapse)</small></div>"
          puts "<div id=inherits_summary><ul>"
          i[:full_inherit].reverse.each do |e|
            link2 = e.to_s.split("::").join("_")+".html" if e.to_s.split("::")[0] == namespace[:name]
            if link2
              puts "<li class=item item_block item_link><a href=#{link2}>&nbsp;&nbsp;#{e}&nbsp;&nbsp;</a></li>"          
            else
              puts "<li class=item item_block item_non_link>#{e}</li>"            
            end
            puts "<br>"
          end
          puts "</ul></div></div>"          
        end
        
        if !i[:includes].empty?
          puts "    <div id=implements_summary_header class=summary_header><b>Implements</b></div>"
          puts "    <div class=implements id=implements>"  
          implements = i[:includes].map do |inc|
            link = inc.data.namespace == @namespace[:name]
            "<div class='implement item'>#{(link ? "      &nbsp;&nbsp;<a href=#{namespace[:name]}_#{inc.data.name}.html>#{inc}</a>" : "#{inc}")}&nbsp;&nbsp</div>"
          end.join("\n\n")
          puts implements
          puts "    </div>"        
        end
        
        if cls
          unless (a=descendants(i)).empty?          
            puts "<div class=summary_header id=descendants_summary_header><b>Known Desendants</b></div>"
            puts "<div class=descendants>"
            a.each do |d|
              link = true
              
              d = link ? "<a href=#{d.split("::").join("_")}.html>#{d}</a>" : d
              puts "<div class='descendant item item_link'>&nbsp;&nbsp;#{d}&nbsp;&nbsp;</div>"
            end
            puts "</div>"
          end   
        else
          unless (a=implemented(i)).empty?          
            puts "<div class=summary_header id=implemented_summary_header><b>Known Implementations</b></div>"
            puts "<div class=implemented>"
            a.each do |d|
              link = true
              
              d = link ? "<a href=#{d.split("::").join("_")}.html>#{d}</a>" : d
              puts "<div class='item item_link'>&nbsp;&nbsp;#{d}&nbsp;&nbsp;</div>"
            end
            puts "</div>"
          end          
        end

        
        generate_method_summary(i,:class)
        generate_method_summary(i)
        generate_signal_summary(i)
    
        generate_methods_details(i,:class)    
        generate_methods_details(i)  
        generate_signals_details(i)  
                                      
                        
        puts FOOTER
        
        file = "#{namespace[:name]}_#{i[:name]}.html"
        
        GLib::File.set_contents file,@buffer.join("\n") 
        
          
      end
    end
  end
end
