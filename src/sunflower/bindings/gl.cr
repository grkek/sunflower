@[Link("epoxy")]
{% if flag?(:darwin) %}
  @[Link(framework: "OpenGL")]
{% end %}
lib LibGL
  # Clear
  fun glClearColor(red : Float32, green : Float32, blue : Float32, alpha : Float32)
  fun glClear(mask : UInt32)
  fun glEnable(cap : UInt32)
  fun glDisable(cap : UInt32)
  fun glBlendFunc(sfactor : UInt32, dfactor : UInt32)
  fun glViewport(x : Int32, y : Int32, width : Int32, height : Int32)

  # Buffers
  fun glGenBuffers(n : Int32, buffers : UInt32*)
  fun glDeleteBuffers(n : Int32, buffers : UInt32*)
  fun glBindBuffer(target : UInt32, buffer : UInt32)
  fun glBufferData(target : UInt32, size : Int64, data : Void*, usage : UInt32)
  fun glBufferSubData(target : UInt32, offset : Int64, size : Int64, data : Void*)

  # VAO
  fun glGenVertexArrays(n : Int32, arrays : UInt32*)
  fun glDeleteVertexArrays(n : Int32, arrays : UInt32*)
  fun glBindVertexArray(array : UInt32)

  # Shaders
  fun glCreateShader(type : UInt32) : UInt32
  fun glDeleteShader(shader : UInt32)
  fun glShaderSource(shader : UInt32, count : Int32, string : UInt8**, length : Int32*)
  fun glCompileShader(shader : UInt32)
  fun glGetShaderiv(shader : UInt32, pname : UInt32, params : Int32*)
  fun glGetShaderInfoLog(shader : UInt32, max_length : Int32, length : Int32*, info_log : UInt8*)

  # Programs
  fun glCreateProgram : UInt32
  fun glDeleteProgram(program : UInt32)
  fun glAttachShader(program : UInt32, shader : UInt32)
  fun glLinkProgram(program : UInt32)
  fun glUseProgram(program : UInt32)
  fun glGetProgramiv(program : UInt32, pname : UInt32, params : Int32*)
  fun glGetProgramInfoLog(program : UInt32, max_length : Int32, length : Int32*, info_log : UInt8*)

  # Uniforms
  fun glGetUniformLocation(program : UInt32, name : UInt8*) : Int32
  fun glUniform1f(location : Int32, v0 : Float32)
  fun glUniform2f(location : Int32, v0 : Float32, v1 : Float32)
  fun glUniform3f(location : Int32, v0 : Float32, v1 : Float32, v2 : Float32)
  fun glUniform4f(location : Int32, v0 : Float32, v1 : Float32, v2 : Float32, v3 : Float32)
  fun glUniformMatrix4fv(location : Int32, count : Int32, transpose : UInt8, value : Float32*)

  # Attributes
  fun glEnableVertexAttribArray(index : UInt32)
  fun glVertexAttribPointer(index : UInt32, size : Int32, type : UInt32, normalized : UInt8, stride : Int32, pointer : Void*)
  fun glGetIntegerv(pname : UInt32, data : Int32*)

  # Draw
  fun glDrawArrays(mode : UInt32, first : Int32, count : Int32)

  # Textures
  fun glGenTextures(n : Int32, textures : UInt32*)
  fun glDeleteTextures(n : Int32, textures : UInt32*)
  fun glBindTexture(target : UInt32, texture : UInt32)
  fun glTexImage2D(target : UInt32, level : Int32, internal_format : Int32, width : Int32, height : Int32, border : Int32, format : UInt32, type : UInt32, data : Void*)
  fun glTexParameteri(target : UInt32, pname : UInt32, param : Int32)
  fun glActiveTexture(texture : UInt32)

  # Error
  fun glGetError : UInt32

  # Constants
  GL_COLOR_BUFFER_BIT    = 0x00004000_u32
  GL_DEPTH_BUFFER_BIT    = 0x00000100_u32
  GL_BLEND               =     0x0BE2_u32
  GL_SRC_ALPHA           =     0x0302_u32
  GL_ONE_MINUS_SRC_ALPHA =     0x0303_u32
  GL_TRIANGLES           =     0x0004_u32
  GL_TRIANGLE_FAN        =     0x0006_u32
  GL_FLOAT               =     0x1406_u32
  GL_UNSIGNED_BYTE       =     0x1401_u32
  GL_FALSE               =           0_u8
  GL_TRUE                =           1_u8
  GL_ARRAY_BUFFER        =     0x8892_u32
  GL_STATIC_DRAW         =     0x88E4_u32
  GL_DYNAMIC_DRAW        =     0x88E8_u32
  GL_VERTEX_SHADER       =     0x8B31_u32
  GL_FRAGMENT_SHADER     =     0x8B30_u32
  GL_COMPILE_STATUS      =     0x8B81_u32
  GL_LINK_STATUS         =     0x8B82_u32
  GL_TEXTURE_2D          =     0x0DE1_u32
  GL_TEXTURE0            =     0x84C0_u32
  GL_TEXTURE_MIN_FILTER  =     0x2801_u32
  GL_TEXTURE_MAG_FILTER  =     0x2800_u32
  GL_LINEAR              =     0x2601_u32
  GL_RGBA                =     0x1908_u32
  GL_RGB                 =     0x1907_u32
end
