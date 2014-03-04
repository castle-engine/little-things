varying vec2 normalMapTexCooord;
uniform sampler2D normalMap;

void PLUG_fragment_eye_space(const vec4 vertex, inout vec3 normal)
{
  normal = texture2D(normalMap, normalMapTexCooord).xyz;

  /* Unpack normal.xy. Blender generates normal maps with Z always > 0,
     so do not unpack Z. Hm, actually, I do not see any visible difference?

     Note: This is normal in tangent space. It so happens that on our
     water surface, this is also valid in object space, because our
     surface is flat on Z=const (and relation of xy to texture st doesn't
     really matter, as it's just a noise for waves, doesn't matter much
     how we map it). So simply transforming by normal_matrix gets us
     into eye-space, and we're happy. */
  normal.xy = normal.xy * 2.0 - vec2(1.0, 1.0);

  if (!gl_FrontFacing) normal.z = -normal.z;

  normal = gl_NormalMatrix * normal;
}

/* void PLUG _texture_apply(inout vec4 fragment_color, const in vec3 normal_eye) */
/* { */
/*   fragment_color.rgb = pow(sin(fragment_color.rgb * 1.57), 0.5); */
/* } */
