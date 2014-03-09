varying vec2 normalMapTexCooord;
void PLUG_vertex_object_space(const in vec4 vertex, const in vec3 normal)
{
  /* funny float consts are to workaround fglrx bugs. */
  normalMapTexCooord = (vertex.xy * 2.0 + vec2(1.0)) / 2.0;
  normalMapTexCooord *= vec2(0.5);
}
