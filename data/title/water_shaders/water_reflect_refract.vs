varying vec3 vertex_to_camera;
varying vec2 reflected_tex_coord;
uniform mat4 cameraInverseMatrix;

void PLUG_vertex_eye_space(const in vec4 vertex_eye,
   const in vec3 normal_eye)
{
  vec4 vertex_world = cameraInverseMatrix * vertex_eye;
  /* The transformation below are specifically done to hit sensible
     point of reflected_tex_coord, they are tied to water and title plane
     positions and sizes. */
  reflected_tex_coord = vec2(vertex_world.x, vertex_world.z);
  reflected_tex_coord /= 60.0;
  reflected_tex_coord.y /= 3.0; // this just looks better
  reflected_tex_coord.xy += vec2(0.5);

  /* That's easy, since in eye space camera position is always (0, 0, 0). */
  vertex_to_camera = normalize(-vec3(vertex_eye));
}
