import 'package:partiu/core/utils/app_localizations.dart';
import 'package:partiu/core/constants/glimpse_colors.dart';
import 'package:partiu/core/constants/glimpse_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partiu/core/constants/constants.dart';
import 'package:dropdown_search/dropdown_search.dart';

/// Widget de seleção de Cidade e Estado (Brasil)
/// Usa dropdown_search com dados de estados e cidades brasileiras
class OriginBrazilianCitySelector extends StatefulWidget {
  const OriginBrazilianCitySelector({
    required this.initialValue,
    required this.onChanged,
    super.key,
  });

  final String? initialValue;
  final ValueChanged<String?> onChanged;

  @override
  State<OriginBrazilianCitySelector> createState() => _OriginBrazilianCitySelectorState();
}

class _OriginBrazilianCitySelectorState extends State<OriginBrazilianCitySelector> {
  String? _selectedState;
  String? _selectedCity;
  
  // Lista de estados brasileiros (siglas)
  static const List<String> _brazilianStates = [
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA',
    'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN',
    'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
  ];
  
  // Mapa de estados para suas cidades (simplificado - principais cidades)
  static const Map<String, List<String>> _stateCities = {
    'AC': ['Rio Branco', 'Cruzeiro do Sul', 'Sena Madureira'],
    'AL': ['Maceió', 'Arapiraca', 'Palmeira dos Índios'],
    'AP': ['Macapá', 'Santana', 'Laranjal do Jari'],
    'AM': ['Manaus', 'Parintins', 'Itacoatiara'],
    'BA': ['Salvador', 'Feira de Santana', 'Vitória da Conquista', 'Camaçari', 'Itabuna', 'Juazeiro'],
    'CE': ['Fortaleza', 'Caucaia', 'Juazeiro do Norte', 'Maracanaú', 'Sobral'],
    'DF': ['Brasília'],
    'ES': ['Vitória', 'Vila Velha', 'Serra', 'Cariacica', 'Cachoeiro de Itapemirim'],
    'GO': ['Goiânia', 'Aparecida de Goiânia', 'Anápolis', 'Rio Verde'],
    'MA': ['São Luís', 'Imperatriz', 'São José de Ribamar', 'Timon'],
    'MT': ['Cuiabá', 'Várzea Grande', 'Rondonópolis', 'Sinop'],
    'MS': ['Campo Grande', 'Dourados', 'Três Lagoas', 'Corumbá'],
    'MG': ['Belo Horizonte', 'Uberlândia', 'Contagem', 'Juiz de Fora', 'Betim', 'Montes Claros'],
    'PA': ['Belém', 'Ananindeua', 'Santarém', 'Marabá', 'Castanhal'],
    'PB': ['João Pessoa', 'Campina Grande', 'Santa Rita', 'Patos'],
    'PR': ['Curitiba', 'Londrina', 'Maringá', 'Ponta Grossa', 'Cascavel', 'Foz do Iguaçu'],
    'PE': ['Recife', 'Jaboatão dos Guararapes', 'Olinda', 'Paulista', 'Caruaru', 'Petrolina'],
    'PI': ['Teresina', 'Parnaíba', 'Picos', 'Floriano'],
    'RJ': ['Rio de Janeiro', 'São Gonçalo', 'Duque de Caxias', 'Nova Iguaçu', 'Niterói', 'Campos dos Goytacazes'],
    'RN': ['Natal', 'Mossoró', 'Parnamirim', 'São Gonçalo do Amarante'],
    'RS': ['Porto Alegre', 'Caxias do Sul', 'Pelotas', 'Canoas', 'Santa Maria', 'Gravataí'],
    'RO': ['Porto Velho', 'Ji-Paraná', 'Ariquemes', 'Cacoal'],
    'RR': ['Boa Vista', 'Rorainópolis', 'Caracaraí'],
    'SC': ['Florianópolis', 'Joinville', 'Blumenau', 'São José', 'Chapecó', 'Criciúma'],
    'SP': ['São Paulo', 'Guarulhos', 'Campinas', 'São Bernardo do Campo', 'Santos', 'Ribeirão Preto', 'Sorocaba'],
    'SE': ['Aracaju', 'Nossa Senhora do Socorro', 'Lagarto', 'Itabaiana'],
    'TO': ['Palmas', 'Araguaína', 'Gurupi', 'Porto Nacional'],
  };

  @override
  void initState() {
    super.initState();
    _parseInitialValue();
  }

  void _parseInitialValue() {
    if (widget.initialValue != null && widget.initialValue!.contains(' - ')) {
      final parts = widget.initialValue!.split(' - ');
      if (parts.length >= 2) {
        _selectedCity = parts[0];
        _selectedState = parts[1];
      }
    }
  }

  void _updateValue() {
    if (_selectedCity != null && _selectedState != null) {
      widget.onChanged('$_selectedCity - $_selectedState');
    } else {
      widget.onChanged(null);
    }
  }
  
  List<String> _getCitiesForState(String? state) {
    if (state == null) return [];
    return _stateCities[state] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Cidade e Estado',
            style: GlimpseStyles.fieldLabelStyle(
              color: GlimpseColors.primaryColorLight,
            ),
          ),
        ),
        
        // Dropdown de Estado
        Container(
          decoration: BoxDecoration(
            color: GlimpseColors.lightTextField,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownSearch<String>(
            items: (filter, infiniteScrollProps) => _brazilianStates,
            selectedItem: _selectedState,
            compareFn: (item1, item2) => item1 == item2,
            suffixProps: const DropdownSuffixProps(
              dropdownButtonProps: DropdownButtonProps(
                iconClosed: Icon(Icons.keyboard_arrow_down, color: GlimpseColors.textSubTitle),
                iconOpened: Icon(Icons.keyboard_arrow_up, color: GlimpseColors.textSubTitle),
              ),
            ),
            popupProps: PopupProps.menu(
              showSearchBox: true,
              searchFieldProps: TextFieldProps(
                decoration: InputDecoration(
                  hintText: 'Buscar Estado',
                  hintStyle: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    color: GlimpseColors.textHint,
                    height: 1.4,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: GlimpseColors.borderColorLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: GlimpseColors.borderColorLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: GlimpseColors.primary, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
              menuProps: MenuProps(
                backgroundColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                elevation: 4,
              ),
              itemBuilder: (context, item, isDisabled, isSelected) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: isSelected ? GlimpseColors.primary.withOpacity(0.1) : Colors.transparent,
                  child: Text(
                    item,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? GlimpseColors.primary : GlimpseColors.primaryColorLight,
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
            decoratorProps: DropDownDecoratorProps(
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
            dropdownBuilder: (context, selectedItem) {
              return Text(
                selectedItem ?? 'Selecione o Estado',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: selectedItem != null 
                      ? GlimpseColors.primaryColorLight 
                      : GlimpseColors.textHint,
                  height: 1.4,
                ),
              );
            },
            onChanged: (String? value) {
              setState(() {
                _selectedState = value;
                _selectedCity = null; // Reset city when state changes
              });
              _updateValue();
            },
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Dropdown de Cidade
        Container(
          decoration: BoxDecoration(
            color: GlimpseColors.lightTextField,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownSearch<String>(
            items: (filter, infiniteScrollProps) => _getCitiesForState(_selectedState),
            selectedItem: _selectedCity,
            enabled: _selectedState != null,
            compareFn: (item1, item2) => item1 == item2,
            suffixProps: const DropdownSuffixProps(
              dropdownButtonProps: DropdownButtonProps(
                iconClosed: Icon(Icons.keyboard_arrow_down, color: GlimpseColors.textSubTitle),
                iconOpened: Icon(Icons.keyboard_arrow_up, color: GlimpseColors.textSubTitle),
              ),
            ),
            popupProps: PopupProps.menu(
              showSearchBox: true,
              searchFieldProps: TextFieldProps(
                decoration: InputDecoration(
                  hintText: 'Buscar Cidade',
                  hintStyle: GoogleFonts.getFont(
                    FONT_PLUS_JAKARTA_SANS,
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    color: GlimpseColors.textHint,
                    height: 1.4,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: GlimpseColors.borderColorLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: GlimpseColors.borderColorLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: GlimpseColors.primary, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
              menuProps: MenuProps(
                backgroundColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
                elevation: 4,
              ),
              itemBuilder: (context, item, isDisabled, isSelected) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: isSelected ? GlimpseColors.primary.withOpacity(0.1) : Colors.transparent,
                  child: Text(
                    item,
                    style: GoogleFonts.getFont(
                      FONT_PLUS_JAKARTA_SANS,
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? GlimpseColors.primary : GlimpseColors.primaryColorLight,
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
            decoratorProps: DropDownDecoratorProps(
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
            dropdownBuilder: (context, selectedItem) {
              return Text(
                selectedItem ?? 'Selecione a Cidade',
                style: GoogleFonts.getFont(
                  FONT_PLUS_JAKARTA_SANS,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: selectedItem != null 
                      ? GlimpseColors.primaryColorLight 
                      : GlimpseColors.textHint,
                  height: 1.4,
                ),
              );
            },
            onChanged: (String? value) {
              setState(() {
                _selectedCity = value;
              });
              _updateValue();
            },
          ),
        ),
      ],
    );
  }
}
