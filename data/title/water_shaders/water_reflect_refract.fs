uniform sampler2D reflectedTexture;
uniform mat3 cameraRotationInverseMatrix;
varying vec2 reflected_tex_coord;

/* Here normal water was sampling cubemap color, we instead use 2D texture. */
vec3 getReflectedColor(vec3 dir)
{
  vec2 coord = reflected_tex_coord + dir.xz / 80.0;
  return texture2D(reflectedTexture, coord).rgb;
}

varying vec3 vertex_to_camera;

void PLUG_main_texture_apply(inout vec4 fragment_color, const in vec3 normal)
{
  /* This will be needed to make later "refractedColor" (input to refract)
     normalize and to make "dot" when calculating refraction_amount fair.

     Note: it's not needed for calculating reflected (color and vector),
     since reflect and textureCube work fine with unnormalized vectors. */
  vec3 to_camera = normalize(vertex_to_camera);

  vec3 reflected = reflect(to_camera, normal);

  /* We have to multiply by cameraRotationInverseMatrix, to get "reflected" from
     eye-space to world-space. Our cube map is generated in world space. */
  reflected = cameraRotationInverseMatrix * reflected;

  /* Why doesn't the reflected need to be negated? Yeah, it works, but why? */
  vec3 reflectedColor = getReflectedColor(-reflected);

  /* fake reflectedColor to be lighter. This just Looks Better. */
  reflectedColor *= 1.5;

  fragment_color.rgb *= reflectedColor;
}
