import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StoreDb.instance.init();
  runApp(const StoreApp());
}

const navy = Color(0xFF17365D);
const bg = Color(0xFFF4F7FB);
const green = Color(0xFF23865A);
const orange = Color(0xFFB96B24);
String money(num n) => '${n.toStringAsFixed(n % 1 == 0 ? 0 : 2)} ج.م';
String dateTime(String s) { try { return DateFormat('dd/MM/yyyy - hh:mm a', 'ar').format(DateTime.parse(s)); } catch (_) { return s; } }

class StoreDb {
  StoreDb._();
  static final instance = StoreDb._();
  Database? db;
  Future<void> init() async {
    final path = p.join(await getDatabasesPath(), 'store_manager_v1.db');
    db = await openDatabase(path, version: 1, onCreate: (d, v) async {
      await d.execute('''CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE UNIQUE, qty INTEGER NOT NULL DEFAULT 0, retail REAL NOT NULL DEFAULT 0, wholesale REAL NOT NULL DEFAULT 0)''');
      await d.execute('''CREATE TABLE logs(id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, product TEXT NOT NULL, qty INTEGER NOT NULL DEFAULT 0, price REAL NOT NULL DEFAULT 0, old_retail REAL, new_retail REAL, old_wholesale REAL, new_wholesale REAL, total REAL NOT NULL DEFAULT 0, created_at TEXT NOT NULL)''');
      await d.execute('''CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT NOT NULL)''');
      await d.insert('settings', {'k':'purchase_pin','v':'1234'});
    });
  }
  Database get d => db!;
  Future<List<Map<String,Object?>>> products([String query = '']) async => d.query('products', where: query.trim().isEmpty ? null : 'name LIKE ?', whereArgs: query.trim().isEmpty ? null : ['%${query.trim()}%'], orderBy: 'name COLLATE NOCASE ASC');
  Future<void> addProduct(String name, int qty, double retail, double wholesale) async {
    await d.insert('products', {'name':name.trim(),'qty':qty,'retail':retail,'wholesale':wholesale}, conflictAlgorithm: ConflictAlgorithm.abort);
  }
  Future<void> sale(Map<String,Object?> product, int qty) async {
    final id = product['id'] as int; final available = product['qty'] as int;
    if (qty < 1 || qty > available) throw Exception('الكمية غير متاحة في المخزون');
    final price = (product['retail'] as num).toDouble(); final now = DateTime.now().toIso8601String();
    await d.transaction((t) async {
      await t.update('products', {'qty':available-qty}, where:'id=?', whereArgs:[id]);
      await t.insert('logs', {'kind':'بيع','product':product['name'],'qty':qty,'price':price,'total':price*qty,'created_at':now});
    });
  }
  Future<void> purchase(Map<String,Object?> product, int qty, double retail, double wholesale) async {
    final id = product['id'] as int; final oldQty = product['qty'] as int; final oldR=(product['retail'] as num).toDouble(); final oldW=(product['wholesale'] as num).toDouble(); final now=DateTime.now().toIso8601String();
    await d.transaction((t) async {
      await t.update('products', {'qty':oldQty+qty,'retail':retail,'wholesale':wholesale}, where:'id=?', whereArgs:[id]);
      await t.insert('logs', {'kind':'شراء','product':product['name'],'qty':qty,'price':retail,'total':retail*qty,'created_at':now});
      if (oldR != retail || oldW != wholesale) await t.insert('logs', {'kind':'تعديل سعر','product':product['name'],'qty':0,'price':retail,'old_retail':oldR,'new_retail':retail,'old_wholesale':oldW,'new_wholesale':wholesale,'total':0,'created_at':now});
    });
  }
  Future<List<Map<String,Object?>>> logs({String? kind, String? day}) async {
    final where=<String>[]; final args=<Object?>[];
    if (kind != null && kind != 'الكل') { where.add('kind=?'); args.add(kind); }
    if (day != null) { where.add("substr(created_at,1,10)=?"); args.add(day); }
    return d.query('logs', where: where.isEmpty ? null : where.join(' AND '), whereArgs: args.isEmpty ? null : args, orderBy:'id DESC');
  }
  Future<String> pin() async { final r=await d.query('settings',where:'k=?',whereArgs:['purchase_pin']); return r.first['v'] as String; }
  Future<void> changePin(String value) async => d.update('settings', {'v':value}, where:'k=?',whereArgs:['purchase_pin']);
}

class StoreApp extends StatelessWidget {
  const StoreApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(title:'إدارة المحل', debugShowCheckedModeBanner:false, theme:ThemeData(useMaterial3:true, colorScheme:ColorScheme.fromSeed(seedColor:navy), scaffoldBackgroundColor:bg, appBarTheme:const AppBarTheme(backgroundColor:bg, foregroundColor:navy, centerTitle:false), cardTheme:CardThemeData(color:Colors.white,elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18))), inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none),contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:14))), locale:const Locale('ar'), supportedLocales:const [Locale('ar'),Locale('en')], localizationsDelegates:const [GlobalMaterialLocalizations.delegate,GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate], home:const HomePage());
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState()=>_HomePageState(); }
class _HomePageState extends State<HomePage> {
  int tab=0; final titles=['الأصناف','المبيعات','المشتريات','سجل العمليات'];
  @override Widget build(BuildContext context) => Scaffold(appBar:AppBar(title:Text(titles[tab],style:const TextStyle(fontWeight:FontWeight.bold)), actions:[if(tab==0) IconButton(onPressed:()=>showProductDialog(context,refresh),icon:const Icon(Icons.add_circle_outline),tooltip:'إضافة صنف')]), body:IndexedStack(index:tab,children:[ProductsPage(key:ValueKey('p$tab'),mode:'أصناف'),ProductsPage(key:ValueKey('s$tab'),mode:'مبيعات'),ProductsPage(key:ValueKey('b$tab'),mode:'مشتريات'),const LogPage()]), bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const [NavigationDestination(icon:Icon(Icons.inventory_2_outlined),selectedIcon:Icon(Icons.inventory_2),label:'الأصناف'),NavigationDestination(icon:Icon(Icons.point_of_sale_outlined),selectedIcon:Icon(Icons.point_of_sale),label:'المبيعات'),NavigationDestination(icon:Icon(Icons.shopping_bag_outlined),selectedIcon:Icon(Icons.shopping_bag),label:'المشتريات'),NavigationDestination(icon:Icon(Icons.history),label:'السجل')]));
  void refresh()=>setState((){});
}

class ProductsPage extends StatefulWidget { final String mode; const ProductsPage({super.key,required this.mode}); @override State<ProductsPage> createState()=>_ProductsPageState(); }
class _ProductsPageState extends State<ProductsPage> {
  final search=TextEditingController(); List<Map<String,Object?>> items=[]; bool loading=true;
  @override void initState(){super.initState();load();search.addListener(load);}
  @override void dispose(){search.dispose();super.dispose();}
  Future<void> load() async { final data=await StoreDb.instance.products(search.text); if(mounted)setState(()=>items=data..sort((a,b)=>(a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()))); }
  @override Widget build(BuildContext context){ final isSales=widget.mode=='مبيعات'; final isPurch=widget.mode=='مشتريات'; return Column(children:[Padding(padding:const EdgeInsets.fromLTRB(16,8,16,12),child:TextField(controller:search,decoration:const InputDecoration(hintText:'ابحث عن اسم الصنف...',prefixIcon:Icon(Icons.search)))), if(isSales||isPurch) Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:Text(isSales?'اختار الصنف لبيع كمية منه':'اختار الصنف لشراء كمية وتحديث الأسعار',style:TextStyle(color:isSales?green:orange,fontWeight:FontWeight.w600))), Expanded(child:items.isEmpty?Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.inventory_2_outlined,size:54,color:Colors.blueGrey.shade200),const SizedBox(height:12),Text(search.text.isEmpty?'مفيش أصناف لسه. اضغط + لإضافة أول صنف.':'مفيش صنف بالاسم ده',style:const TextStyle(color:Colors.blueGrey))])):ListView.separated(padding:const EdgeInsets.fromLTRB(12,0,12,16),itemCount:items.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(context,i){final x=items[i]; final qty=x['qty'] as int; final r=(x['retail'] as num).toDouble(); final w=(x['wholesale'] as num).toDouble(); return Card(child:InkWell(borderRadius:BorderRadius.circular(18),onTap:()=>isSales?saleDialog(context,x,load):isPurch?purchaseDialog(context,x,load):showProductDialog(context,load,product:x),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(x['name'] as String,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17))),Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),decoration:BoxDecoration(color:qty<=3?const Color(0xFFFFE9E6):const Color(0xFFE5F5EC),borderRadius:BorderRadius.circular(20)),child:Text('الكمية: $qty',style:TextStyle(color:qty<=3?Colors.red.shade700:green,fontWeight:FontWeight.w700)))]),const SizedBox(height:12),Row(children:[Expanded(child:priceTile('سعر القطاعي',money(r),const Color(0xFF3978C6))),const SizedBox(width:8),Expanded(child:priceTile('سعر الجملة',money(w),const Color(0xFF8265C7))),const SizedBox(width:8),Expanded(child:priceTile('إجمالي القطاعي',money(qty*r),green))]),if(isSales||isPurch) Padding(padding:const EdgeInsets.only(top:10),child:Row(mainAxisAlignment:MainAxisAlignment.end,children:[Text(isSales?'اضغط لتسجيل بيع':'اضغط لتسجيل شراء',style:TextStyle(color:isSales?green:orange,fontWeight:FontWeight.bold)),const SizedBox(width:5),Icon(Icons.chevron_left,color:isSales?green:orange)]))]))));}) )]); }
}
Widget priceTile(String label,String value,Color c)=>Container(padding:const EdgeInsets.all(9),decoration:BoxDecoration(color:c.withOpacity(.08),borderRadius:BorderRadius.circular(12)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(fontSize:10,color:Colors.black54)),const SizedBox(height:4),FittedBox(fit:BoxFit.scaleDown,alignment:Alignment.centerRight,child:Text(value,style:TextStyle(color:c,fontWeight:FontWeight.bold,fontSize:12)))]));

Future<void> showProductDialog(BuildContext context,VoidCallback refresh,{Map<String,Object?>? product}) async { final name=TextEditingController(text:product?['name'] as String? ?? ''); final qty=TextEditingController(text:product?['qty'].toString() ?? '0'); final retail=TextEditingController(text:product?['retail'].toString() ?? '0'); final wholesale=TextEditingController(text:product?['wholesale'].toString() ?? '0'); final form=GlobalKey<FormState>(); final result=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(product==null?'إضافة صنف جديد':'تعديل بيانات الصنف'),content:Form(key:form,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[field(name,'اسم الصنف'),field(qty,'الكمية',numeric:true),field(retail,'سعر القطاعي',numeric:true),field(wholesale,'سعر الجملة',numeric:true)]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:(){if(form.currentState!.validate())Navigator.pop(ctx,true);},child:const Text('حفظ'))])); if(result!=true)return; try {if(product==null){await StoreDb.instance.addProduct(name.text,int.parse(qty.text),double.parse(retail.text),double.parse(wholesale.text));}else{final pin=await askPin(context); if(pin==null)return; if(pin!=await StoreDb.instance.pin()){if(context.mounted)snack(context,'الباسورد غير صحيح');return;} final oldR=(product['retail'] as num).toDouble(); final newR=double.parse(retail.text); final oldW=(product['wholesale'] as num).toDouble(); final newW=double.parse(wholesale.text); await StoreDb.instance.d.update('products',{'qty':int.parse(qty.text),'retail':newR,'wholesale':newW},where:'id=?',whereArgs:[product['id']]); if(oldR!=newR||oldW!=newW)await StoreDb.instance.d.insert('logs',{'kind':'تعديل سعر','product':name.text,'qty':0,'price':newR,'old_retail':oldR,'new_retail':newR,'old_wholesale':oldW,'new_wholesale':newW,'total':0,'created_at':DateTime.now().toIso8601String()});} refresh(); if(context.mounted)snack(context,'تم الحفظ بنجاح');}catch(e){if(context.mounted)snack(context,e.toString().contains('UNIQUE')?'اسم الصنف موجود بالفعل':'حصل خطأ أثناء الحفظ');}}
Widget field(TextEditingController c,String label,{bool numeric=false})=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextFormField(controller:c,keyboardType:numeric?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,validator:(v){if(v==null||v.trim().isEmpty)return'اكتب $label';if(numeric&&(double.tryParse(v)==null||double.parse(v)<0))return'اكتب رقم صحيح';return null;},decoration:InputDecoration(labelText:label)));

Future<void> saleDialog(BuildContext context,Map<String,Object?> product,VoidCallback refresh) async {final q=TextEditingController(text:'1');final form=GlobalKey<FormState>();final n=await showDialog<int>(context:context,builder:(ctx)=>AlertDialog(title:Text('بيع ${product['name']}'),content:Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('المتاح في المخزن: ${product['qty']}'),const SizedBox(height:12),TextFormField(controller:q,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الكمية المباعة'),validator:(v){final a=int.tryParse(v??'');if(a==null||a<1)return'اكتب كمية صحيحة';if(a>(product['qty'] as int))return'الكمية أكبر من المتاح';return null;})])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:(){if(form.currentState!.validate())Navigator.pop(ctx,int.parse(q.text));},child:const Text('حفظ البيع'))]));if(n==null)return;try{await StoreDb.instance.sale(product,n);refresh();if(context.mounted)snack(context,'تم تسجيل البيع وتحديث المخزون');}catch(e){if(context.mounted)snack(context,e.toString());}}

Future<void> purchaseDialog(BuildContext context,Map<String,Object?> product,VoidCallback refresh) async {final pin=await askPin(context);if(pin==null)return;if(pin!=await StoreDb.instance.pin()){if(context.mounted)snack(context,'الباسورد غير صحيح');return;}final q=TextEditingController(text:'1');final r=TextEditingController(text:product['retail'].toString());final w=TextEditingController(text:product['wholesale'].toString());final form=GlobalKey<FormState>();final values=await showDialog<List<double>>(context:context,builder:(ctx)=>AlertDialog(title:Text('شراء ${product['name']}'),content:Form(key:form,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[Text('الكمية الحالية: ${product['qty']}',style:const TextStyle(color:Colors.blueGrey)),field(q,'الكمية المشتراة',numeric:true),field(r,'سعر القطاعي الجديد',numeric:true),field(w,'سعر الجملة الجديد',numeric:true)]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:(){if(form.currentState!.validate()&&int.parse(q.text)>0)Navigator.pop(ctx,[int.parse(q.text).toDouble(),double.parse(r.text),double.parse(w.text)]);},child:const Text('حفظ الشراء'))]));if(values==null)return;try{await StoreDb.instance.purchase(product,values[0].toInt(),values[1],values[2]);refresh();if(context.mounted)snack(context,'تم تسجيل الشراء وتحديث المخزون');}catch(e){if(context.mounted)snack(context,'حصل خطأ أثناء الحفظ');}}

Future<String?> askPin(BuildContext context) async {final c=TextEditingController();return showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('إدخال باسورد المشتريات'),content:TextField(controller:c,obscureText:true,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'الباسورد')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text),child:const Text('تأكيد'))]));}
void snack(BuildContext context,String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),behavior:SnackBarBehavior.floating));

class LogPage extends StatefulWidget {const LogPage({super.key});@override State<LogPage> createState()=>_LogPageState();}
class _LogPageState extends State<LogPage>{String kind='الكل';DateTime? day;List<Map<String,Object?>> rows=[];@override void initState(){super.initState();load();}Future<void> load()async{final k=kind;final d=day==null?null:'${day!.year.toString().padLeft(4,'0')}-${day!.month.toString().padLeft(2,'0')}-${day!.day.toString().padLeft(2,'0')}';final a=await StoreDb.instance.logs(kind:k,day:d);if(mounted)setState(()=>rows=a);}
@override Widget build(BuildContext context)=>Column(children:[Padding(padding:const EdgeInsets.fromLTRB(14,8,14,12),child:Column(children:[DropdownButtonFormField<String>(value:kind,decoration:const InputDecoration(labelText:'نوع العمليات'),items:const ['الكل','بيع','شراء','تعديل سعر'].map((x)=>DropdownMenuItem(value:x,child:Text(x=='الكل'?'كل العمليات':x))).toList(),onChanged:(v){kind=v??'الكل';load();}),const SizedBox(height:8),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()async{final d=await showDatePicker(context:context,initialDate:day??DateTime.now(),firstDate:DateTime(2020),lastDate:DateTime(2100),locale:const Locale('ar'));if(d!=null){day=d;load();}},icon:const Icon(Icons.calendar_month),label:Text(day==null?'اختيار يوم':DateFormat('dd/MM/yyyy').format(day!)))),if(day!=null)IconButton(onPressed:(){day=null;load();},icon:const Icon(Icons.close),tooltip:'إلغاء التاريخ')])])),Expanded(child:rows.isEmpty?const Center(child:Text('لا توجد عمليات مسجلة للفترة المختارة',style:TextStyle(color:Colors.blueGrey))):ListView.separated(padding:const EdgeInsets.fromLTRB(12,0,12,16),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(context,i){final x=rows[i];final k=x['kind'] as String;final isSale=k=='بيع';final isBuy=k=='شراء';final color=isSale?const Color(0xFFD9534F):isBuy?green:const Color(0xFF8265C7);final q=x['qty'] as int;final product=x['product'] as String;String detail;if(k=='تعديل سعر'){detail='القطاعي: ${money((x['old_retail'] as num?)??0)} ← ${money((x['new_retail'] as num?)??0)}\nالجملة: ${money((x['old_wholesale'] as num?)??0)} ← ${money((x['new_wholesale'] as num?)??0)}';}else{detail='${isSale?'تم بيع':'تم شراء'} $q من $product\nسعر الوحدة: ${money((x['price'] as num).toDouble())} • الإجمالي: ${money((x['total'] as num).toDouble())}';}return Card(child:Padding(padding:const EdgeInsets.all(14),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Container(width:42,height:42,decoration:BoxDecoration(color:color.withOpacity(.1),borderRadius:BorderRadius.circular(13)),child:Icon(isSale?Icons.remove_shopping_cart:isBuy?Icons.add_shopping_cart:Icons.price_change,color:color)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(k=='تعديل سعر'?'تعديل سعر $product':'$k — $product',style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:5),Text(detail,style:const TextStyle(height:1.5)),const SizedBox(height:6),Text(dateTime(x['created_at'] as String),style:const TextStyle(fontSize:11,color:Colors.blueGrey))]))])));} ))]);}
